defmodule Caravela.Live.Template do
  @moduledoc """
  `use` macro that binds a Phoenix LiveView to a `Caravela.Live.Domain`
  module.

  Injects a default `mount/3` (assigning the domain's initial state)
  and a default `handle_event/3` that dispatches to the domain's
  `on_event` handlers. Also imports `apply_updater/2,3`, sugar around
  `Caravela.Live.Updater.apply/2,3` that looks up updaters by name on
  the bound domain.

      defmodule MyAppWeb.BookEditorLive do
        use MyAppWeb, :live_view
        use Caravela.Live.Template, domain: MyApp.BookEditorDomain

        def render(assigns) do
          ~H\"\"\"
          <CaravelaSvelte.svelte
            name="library/BookEditor"
            props={%{book: @book, saving: @saving}}
            socket={@socket}
          />
          \"\"\"
        end
      end

  The Svelte component's `pushEvent` calls arrive as LiveView events
  and are routed through the domain's `on_event` handlers. If no
  handler matches, the default `handle_event/3` lets the LiveView's
  own (developer-written) clauses take over via Elixir's normal
  clause-matching — this macro only adds a catch-all at the bottom.
  """

  @doc false
  defmacro __using__(opts) do
    domain = Keyword.fetch!(opts, :domain)

    quote bind_quoted: [domain: domain] do
      @caravela_live_domain domain

      import Caravela.Live.Template, only: [apply_updater: 2, apply_updater: 3]

      @impl Phoenix.LiveView
      def mount(_params, _session, socket) do
        defaults = unquote(domain).__caravela_live_state__()
        {:ok, Caravela.Live.Template.__assign_defaults__(socket, defaults)}
      end

      @impl Phoenix.LiveView
      def handle_event(event, params, socket) do
        case unquote(domain).__caravela_live_event__(event, socket, params) do
          %{assigns: _} = updated_socket ->
            {:noreply, updated_socket}

          {:noreply, _} = tuple ->
            tuple

          {:reply, _, _} = tuple ->
            tuple

          {:error, {:no_such_event, ev}} ->
            require Logger
            Logger.warning("Caravela.Live.Template: no on_event handler for #{inspect(ev)}")
            {:noreply, socket}
        end
      end

      @impl Phoenix.LiveView
      def handle_info(msg, socket) do
        case unquote(domain).__caravela_live_info__(msg, socket) do
          %{assigns: _} = updated_socket -> {:noreply, updated_socket}
          {:noreply, _} = tuple -> tuple
        end
      end

      defoverridable mount: 3, handle_event: 3, handle_info: 2
    end
  end

  @doc """
  Apply a named updater to the socket. The name is resolved against the
  `Caravela.Live.Domain` module bound at `use` time.

      def handle_event("save", _params, socket) do
        {:noreply, socket |> apply_updater(:mark_saving)}
      end

  Raises if the name isn't registered on the domain.
  """
  defmacro apply_updater(socket, updater_name) do
    quote do
      Caravela.Live.Template.__apply_updater__(
        unquote(socket),
        unquote(updater_name),
        @caravela_live_domain
      )
    end
  end

  @doc """
  Apply a named 2-arity updater with an event-payload argument.

      socket |> apply_updater(:set_book, book)
  """
  defmacro apply_updater(socket, updater_name, arg) do
    quote do
      Caravela.Live.Template.__apply_updater__(
        unquote(socket),
        unquote(updater_name),
        unquote(arg),
        @caravela_live_domain
      )
    end
  end

  @doc false
  def __apply_updater__(socket, name, domain) do
    case domain.__caravela_live_updater__(name) do
      nil ->
        raise ArgumentError,
              "no updater #{inspect(name)} defined on #{inspect(domain)}"

      fun when is_function(fun, 1) ->
        Caravela.Live.Updater.run(socket, fun)

      fun when is_function(fun, 2) ->
        raise ArgumentError,
              "updater #{inspect(name)} on #{inspect(domain)} takes an argument — " <>
                "use apply_updater(socket, #{inspect(name)}, arg)"
    end
  end

  @doc false
  def __apply_updater__(socket, name, arg, domain) do
    case domain.__caravela_live_updater__(name) do
      nil ->
        raise ArgumentError,
              "no updater #{inspect(name)} defined on #{inspect(domain)}"

      fun when is_function(fun, 2) ->
        Caravela.Live.Updater.run(socket, fun, arg)

      fun when is_function(fun, 1) ->
        raise ArgumentError,
              "updater #{inspect(name)} on #{inspect(domain)} takes no argument — " <>
                "use apply_updater(socket, #{inspect(name)})"
    end
  end

  @doc false
  def __assign_defaults__(socket, defaults) when is_map(defaults) do
    if is_struct(socket) and Code.ensure_loaded?(Phoenix.LiveView.Socket) and
         socket.__struct__ == Phoenix.LiveView.Socket do
      Phoenix.Component.assign(socket, defaults)
    else
      %{socket | assigns: Map.merge(Map.get(socket, :assigns, %{}), defaults)}
    end
  end
end
