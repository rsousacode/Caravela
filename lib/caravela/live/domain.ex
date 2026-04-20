defmodule Caravela.Live.Domain do
  @moduledoc """
  DSL for declaring a server-side state machine that a LiveView can mount
  via `Caravela.Live.Template`. Mirrors the Ballerina "domain logic"
  layer: state fields, named updaters that transition the state, and
  event handlers that run on messages pushed from the Svelte side.

      defmodule MyApp.BookEditorDomain do
        use Caravela.Live.Domain

        state do
          field :book, :map, default: %{}
          field :saving, :boolean, default: false
          field :flash_message, :string, default: nil
        end

        updater :mark_saving, fn assigns -> %{assigns | saving: true} end
        updater :mark_saved,  fn assigns -> %{assigns | saving: false, flash_message: "Saved!"} end
        updater :set_book,    fn assigns, book -> %{assigns | book: book} end

        # Inside on_event we have the full `apply_updater/2,3` sugar -
        # Caravela.Live.Domain's `use` block sets `@caravela_live_domain
        # __MODULE__`, so the macro resolves updater names against this
        # module without an explicit third argument.
        on_event "save", fn socket ->
          apply_updater(socket, :mark_saving)
        end

        on_event "set_book", fn socket, %{"book" => book} ->
          apply_updater(socket, :set_book, book)
        end

        on_info {:saved, book}, fn socket ->
          socket
          |> apply_updater(:set_book, book)
          |> apply_updater(:mark_saved)
        end
      end

  After compilation the module exposes four lookup functions consumed
  by `Caravela.Live.Template`:

    * `__caravela_live_state__/0` - default assigns map from `state do ... end`
    * `__caravela_live_updater__/1` - returns the updater function for a name, or `nil`
    * `__caravela_live_event__/3` - dispatches an event name to its handler, returning a socket
    * `__caravela_live_info__/2` - dispatches an async message (`handle_info`) to its handler

  Updater functions are stored as literal `fn`s, so they can be composed
  with `Caravela.Live.Updater.compose/2` or piped through the `~>`
  operator as needed.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Caravela.Live.Domain,
        only: [
          state: 1,
          field: 2,
          field: 3,
          updater: 2,
          on_event: 2,
          on_info: 2
        ]

      # Mirror the attribute Caravela.Live.Template sets on LiveView
      # modules: when present on the CURRENT module, the
      # `Caravela.Live.Template.apply_updater/2,3` macros resolve
      # updater names against it. Setting it to `__MODULE__` here lets
      # `on_event`/`on_info` bodies call `apply_updater(socket, :name)`
      # without specifying the domain explicitly.
      @caravela_live_domain __MODULE__

      import Caravela.Live.Template, only: [apply_updater: 2, apply_updater: 3]

      Module.register_attribute(__MODULE__, :caravela_live_state, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_live_updaters, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_live_events, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_live_infos, accumulate: true)

      @before_compile Caravela.Live.Domain
    end
  end

  @doc """
  Declare the default state fields - the assigns map a mounted LiveView
  starts with. Each `field/2,3` inside `state do ... end` contributes
  one key/default pair.

      state do
        field :books, :list, default: []
        field :loading, :boolean, default: false
      end
  """
  defmacro state(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Declare a field on the domain state. `type` is an informational tag
  only (for future typed-prop codegen). `opts` may include
  `default:` - the value used when the domain mounts.

      field :saving, :boolean, default: false
  """
  defmacro field(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      unless is_atom(name), do: raise(ArgumentError, "field name must be an atom")

      @caravela_live_state {name, type, Keyword.get(opts, :default)}
    end
  end

  @doc """
  Declare a named updater. The function must take the assigns map and
  return a new assigns map, optionally with an extra event-payload
  argument.

      updater :mark_saving, fn assigns -> %{assigns | saving: true} end
      updater :set_book,    fn assigns, book -> %{assigns | book: book} end
  """
  defmacro updater(name, fun) do
    arity = fun_arity_or_raise!(fun, [1, 2], :updater)

    quote do
      @caravela_live_updaters {unquote(name), unquote(arity)}
      def __caravela_live_updater__(unquote(name)), do: unquote(fun)
    end
  end

  @doc """
  Declare an event handler matching a LiveSvelte/LiveView event name.

  The handler must accept a socket (and optionally a params map):

      on_event "save", fn socket -> ... end
      on_event "validate", fn socket, %{"field" => f, "value" => v} -> ... end

  Generated `__caravela_live_event__/3` dispatches on the event name and
  returns the updated socket.
  """
  defmacro on_event(event, fun) do
    unless is_binary(event) do
      raise Caravela.DSLError,
        message: "`on_event` name must be a string literal, got: #{inspect(event)}",
        suggestion: "on_event \"save\", fn socket, _params -> socket end",
        docs_url: "https://hexdocs.pm/caravela/live_runtime.html#on_event"
    end

    arity = fun_arity_or_raise!(fun, [1, 2], :on_event)

    case arity do
      1 ->
        quote do
          @caravela_live_events {unquote(event), 1}
          def __caravela_live_event__(unquote(event), socket, _params) do
            unquote(fun).(socket)
          end
        end

      2 ->
        quote do
          @caravela_live_events {unquote(event), 2}
          def __caravela_live_event__(unquote(event), socket, params) do
            unquote(fun).(socket, params)
          end
        end
    end
  end

  @doc """
  Declare an async-message handler matching a value sent to the
  LiveView process (via `send/2`, `Phoenix.PubSub.broadcast`, etc.).

  The handler accepts the socket and must return a socket:

      on_info {:saved, book}, fn socket -> apply_updater(socket, :mark_saved) end

  The first argument is a match pattern on the inbound message. It can
  be any Elixir pattern the compiler accepts (tuples, atoms, maps).
  """
  defmacro on_info(pattern, fun) do
    arity = fun_arity_or_raise!(fun, [1], :on_info)
    _ = arity

    quote do
      @caravela_live_infos {unquote(Macro.to_string(pattern)), 1}
      def __caravela_live_info__(unquote(pattern), socket) do
        unquote(fun).(socket)
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    state = env.module |> Module.get_attribute(:caravela_live_state) |> Enum.reverse()
    updaters = env.module |> Module.get_attribute(:caravela_live_updaters) |> Enum.reverse()
    events = env.module |> Module.get_attribute(:caravela_live_events) |> Enum.reverse()
    infos = env.module |> Module.get_attribute(:caravela_live_infos) |> Enum.reverse()

    default_assigns =
      state
      |> Enum.map(fn {name, _type, default} -> {name, default} end)
      |> Enum.into(%{})

    quote do
      @doc false
      def __caravela_live_state__, do: unquote(Macro.escape(default_assigns))

      @doc false
      def __caravela_live_state_fields__,
        do: unquote(Macro.escape(Enum.map(state, fn {n, t, _} -> {n, t} end)))

      @doc false
      def __caravela_live_updaters__, do: unquote(Macro.escape(updaters))

      @doc false
      def __caravela_live_events__, do: unquote(Macro.escape(events))

      @doc false
      def __caravela_live_infos__, do: unquote(Macro.escape(infos))

      # Fallback clauses - come after the specific ones injected by
      # each `updater`/`on_event`/`on_info` call.
      def __caravela_live_updater__(_name), do: nil

      def __caravela_live_event__(event, _socket, _params),
        do: {:error, {:no_such_event, event}}

      def __caravela_live_info__(_msg, socket), do: socket
    end
  end

  # --- Internal helpers ----------------------------------------------------

  # Narrowed clone of Caravela.Domain.fun_arity - both modules use it to
  # validate user-supplied function literals at compile time. Accepts
  # anonymous `fn` and captures.
  defp fun_arity_or_raise!(fun, allowed, macro_name) do
    case arity_of(fun) do
      {:ok, a} when is_integer(a) ->
        if a in allowed do
          a
        else
          raise Caravela.DSLError,
            message:
              "`#{macro_name}` requires a function of arity in " <>
                "#{inspect(allowed)}, got arity #{a}",
            suggestion: "on_event \"save\", fn socket, _params -> socket end",
            docs_url: "https://hexdocs.pm/caravela/live_runtime.html"
        end

      :unknown ->
        raise Caravela.DSLError,
          message:
            "`#{macro_name}` requires a literal `fn ... end` or `&Module.fun/N` " <>
              "capture so arity can be checked at compile time. Got: " <>
              Macro.to_string(fun),
          suggestion:
            "To pass a bound function variable, wrap it:\n" <>
              "    fn arg -> my_fun.(arg) end",
          docs_url: "https://hexdocs.pm/caravela/live_runtime.html"
    end
  end

  defp arity_of({:fn, _, clauses}) when is_list(clauses) do
    arities =
      Enum.map(clauses, fn
        {:->, _, [args, _body]} when is_list(args) -> length(args)
        _ -> :bad
      end)

    cond do
      Enum.any?(arities, &(&1 == :bad)) -> :unknown
      arities == [] -> :unknown
      Enum.uniq(arities) |> length() == 1 -> {:ok, hd(arities)}
      true -> :unknown
    end
  end

  defp arity_of({:&, _, [{:/, _, [_, arity]}]}) when is_integer(arity), do: {:ok, arity}

  defp arity_of({:&, _, [body]}) do
    case max_capture(body, 0) do
      0 -> :unknown
      n -> {:ok, n}
    end
  end

  defp arity_of(_), do: :unknown

  defp max_capture({:&, _, [n]}, acc) when is_integer(n), do: max(acc, n)
  defp max_capture({_, _, args}, acc) when is_list(args), do: max_in_args(args, acc)
  defp max_capture(list, acc) when is_list(list), do: max_in_args(list, acc)
  defp max_capture({a, b}, acc), do: max_capture(b, max_capture(a, acc))
  defp max_capture(_, acc), do: acc

  defp max_in_args(args, acc) do
    Enum.reduce(args, acc, fn arg, a -> max_capture(arg, a) end)
  end
end
