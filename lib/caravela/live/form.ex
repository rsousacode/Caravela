defmodule Caravela.Live.Form do
  @moduledoc """
  DSL for declaring form-visibility predicates and async-validation
  rules on top of `Caravela.Live.Domain`.

  A form-domain module compiles into a regular `Caravela.Live.Domain`
  (so all state/updater/event sugar is available) plus a small amount
  of form-specific introspection consumed by the Svelte form generator
  (`Caravela.Gen.SvelteForm`) and by the form LiveView at runtime.

      defmodule MyApp.BookFormDomain do
        use Caravela.Live.Form,
          entity: MyApp.Library.V1.Book,
          context_fields: [:current_user]

        state do
          field :book, :map, default: nil
          field :attrs, :map, default: %{}
          field :errors, :map, default: %{}
          field :field_visibility, :map, default: %{}
          field :async_errors, :map, default: %{}
          field :saving, :boolean, default: false
          field :flash_message, :string, default: nil
        end

        visible :published_at, fn assigns ->
          Map.get(assigns.attrs, :published) == true
        end

        visible :price, fn assigns ->
          assigns.current_user.role in [:admin, :editor]
        end

        validate_async :isbn, debounce: 500, fn value, _assigns ->
          case MyApp.ISBNService.validate(value) do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
          end
        end
      end

  After compilation the module exposes:

    * `__caravela_form__/0` — form metadata (entity, context fields,
      visible/async field lists, debounces).
    * `__caravela_form_visibility__/1` — compute the `field_visibility`
      map from an assigns map by running every `visible` predicate.
    * `__caravela_form_visible__/2` — per-field visibility predicate
      (fallback returns `true` for undeclared fields).
    * `__caravela_form_validate_async__/3` — dispatches a field's
      async validator; returns `:ok` or `{:error, reason}`.
  """

  @doc false
  defmacro __using__(opts) do
    entity = Keyword.get(opts, :entity)
    context_fields = Keyword.get(opts, :context_fields, [])

    quote do
      use Caravela.Live.Domain

      import Caravela.Live.Form,
        only: [visible: 2, validate_async: 2, validate_async: 3]

      Module.register_attribute(__MODULE__, :caravela_form_visibilities, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_form_async, accumulate: true)

      @caravela_form_entity unquote(entity)
      @caravela_form_context_fields unquote(context_fields)

      @before_compile Caravela.Live.Form
    end
  end

  @doc """
  Declare a visibility predicate for a field. The function receives the
  LiveView assigns and must return a boolean.

      visible :published_at, fn assigns ->
        Map.get(assigns.attrs, :published) == true
      end

  The predicate is evaluated server-side; the computed truth value is
  sent to the Svelte component as `field_visibility.<name>` so that
  `{#if field_visibility.published_at}` renders reactively.
  """
  defmacro visible(field, fun) do
    unless is_atom(field) do
      raise ArgumentError, "visible name must be an atom, got: #{inspect(field)}"
    end

    _ = fun_arity_or_raise!(fun, [1], :visible)

    quote do
      @caravela_form_visibilities unquote(field)

      def __caravela_form_visible__(unquote(field), assigns) do
        unquote(fun).(assigns)
      end
    end
  end

  @doc """
  Declare an async validator for a field.

      validate_async :isbn, debounce: 500, fn value, assigns ->
        MyApp.ISBNService.validate(value)
      end

  The validator is a function of arity 2 (`value`, `assigns`) that
  returns `:ok` or `{:error, reason}`. The optional `:debounce` option
  (milliseconds) is exposed as metadata so the generated Svelte form
  can debounce client-side input before pushing the
  `"validate_async"` event back to the LiveView.
  """
  defmacro validate_async(field, opts \\ [], fun) do
    unless is_atom(field) do
      raise ArgumentError, "validate_async name must be an atom, got: #{inspect(field)}"
    end

    unless is_list(opts) do
      raise ArgumentError,
            "validate_async opts must be a keyword list, got: #{inspect(opts)}"
    end

    debounce = Keyword.get(opts, :debounce, 0)

    unless is_integer(debounce) and debounce >= 0 do
      raise ArgumentError,
            "validate_async :debounce must be a non-negative integer, got: #{inspect(debounce)}"
    end

    _ = fun_arity_or_raise!(fun, [2], :validate_async)

    quote do
      @caravela_form_async {unquote(field), unquote(debounce)}

      def __caravela_form_validate_async__(unquote(field), value, assigns) do
        unquote(fun).(value, assigns)
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    visible_fields =
      env.module |> Module.get_attribute(:caravela_form_visibilities) |> Enum.reverse()

    async = env.module |> Module.get_attribute(:caravela_form_async) |> Enum.reverse()
    entity = Module.get_attribute(env.module, :caravela_form_entity)
    context_fields = Module.get_attribute(env.module, :caravela_form_context_fields) || []

    async_fields = Enum.map(async, fn {f, _d} -> f end)
    debounces = Map.new(async, fn {f, d} -> {f, d} end)

    quote do
      @doc false
      def __caravela_form__ do
        %{
          entity: unquote(entity),
          context_fields: unquote(context_fields),
          visible_fields: unquote(visible_fields),
          async_fields: unquote(async_fields),
          debounces: unquote(Macro.escape(debounces))
        }
      end

      @doc """
      Compute the `field_visibility` map from an assigns map. For each
      field declared with `visible/2`, the predicate is evaluated; the
      result is stored in the map under the field's name. Fields
      without a predicate default to `true`.
      """
      def __caravela_form_visibility__(assigns) do
        Enum.reduce(unquote(visible_fields), %{}, fn field, acc ->
          Map.put(acc, field, __caravela_form_visible__(field, assigns))
        end)
      end

      # Fallback clauses — matched only after specific clauses injected
      # by each `visible/2` and `validate_async/2,3` macro call.
      def __caravela_form_visible__(_field, _assigns), do: true
      def __caravela_form_validate_async__(_field, _value, _assigns), do: :ok
    end
  end

  # --- Internal helpers ----------------------------------------------------

  # Mirrors Caravela.Live.Domain's narrowed arity checker so Form
  # bodies accept the same fn / capture shapes.
  defp fun_arity_or_raise!(fun, allowed, macro_name) do
    case arity_of(fun) do
      {:ok, a} when is_integer(a) ->
        if a in allowed do
          a
        else
          raise ArgumentError,
                "Caravela: #{macro_name} requires a function of arity in " <>
                  "#{inspect(allowed)}, got arity #{a}"
        end

      :unknown ->
        raise ArgumentError,
              "Caravela: #{macro_name} requires a function literal, got: " <>
                Macro.to_string(fun)
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
