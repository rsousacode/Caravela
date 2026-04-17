defmodule Caravela.Domain do
  @moduledoc """
  DSL entry point. `use Caravela.Domain` in a module to declare a domain:

      defmodule MyApp.Domains.Library do
        use Caravela.Domain

        entity :authors do
          field :name, :string, required: true
          field :bio, :text
        end

        entity :books do
          field :title, :string, required: true, min_length: 3
          field :isbn, :string, format: ~r/^\\d{13}$/
        end

        relation :authors, :books, type: :has_many

        on_create :books, fn changeset, _context ->
          Ecto.Changeset.validate_required(changeset, [:title])
        end

        can_create :books, fn context ->
          context.current_user.role in [:admin, :editor]
        end
      end

  After compilation the module exposes `__caravela_domain__/0`, returning
  the validated `Caravela.Schema.Domain` IR, plus `__caravela_hook__/4`
  and `__caravela_permission__` clauses for every declared hook and
  permission.
  """

  @hook_actions [:on_create, :on_update, :on_delete]
  @permission_actions [:can_read, :can_create, :can_update, :can_delete]

  # Expected function arity for each action.
  @hook_arity %{on_create: 2, on_update: 2, on_delete: 2}
  @permission_arity %{can_read: 2, can_create: 1, can_update: 2, can_delete: 2}

  @doc false
  def hook_actions, do: @hook_actions
  @doc false
  def permission_actions, do: @permission_actions
  @doc false
  def hook_arity(action), do: Map.fetch!(@hook_arity, action)
  @doc false
  def permission_arity(action), do: Map.fetch!(@permission_arity, action)

  defmacro __using__(opts) do
    quote do
      import Caravela.Domain,
        only: [
          entity: 2,
          field: 2,
          field: 3,
          relation: 3,
          on_create: 2,
          on_update: 2,
          on_delete: 2,
          can_read: 2,
          can_create: 2,
          can_update: 2,
          can_delete: 2
        ]

      Module.register_attribute(__MODULE__, :caravela_entities, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_relations, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_hooks, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_permissions, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_domain_opts, persist: false)
      Module.register_attribute(__MODULE__, :caravela_current_fields, persist: false)

      @caravela_domain_opts unquote(opts)
      @before_compile Caravela.Compiler
    end
  end

  @doc """
  Declare an entity (a table/schema) with a `do` block of fields.

      entity :books do
        field :title, :string, required: true
      end
  """
  defmacro entity(name, do: block) do
    quote do
      @caravela_current_fields []
      unquote(block)
      fields = Enum.reverse(Module.get_attribute(__MODULE__, :caravela_current_fields))

      @caravela_entities %Caravela.Schema.Entity{
        name: unquote(name),
        fields: fields
      }

      Module.delete_attribute(__MODULE__, :caravela_current_fields)
    end
  end

  @doc """
  Declare a field inside an `entity` block.

      field :title, :string, required: true, min_length: 3
  """
  defmacro field(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      unless is_atom(name), do: raise(ArgumentError, "field name must be an atom")
      unless is_atom(type), do: raise(ArgumentError, "field type must be an atom")

      entry = %Caravela.Schema.Field{name: name, type: type, opts: opts}
      current = Module.get_attribute(__MODULE__, :caravela_current_fields) || []
      Module.put_attribute(__MODULE__, :caravela_current_fields, [entry | current])
    end
  end

  @doc """
  Declare a relation between two entities.

      relation :authors, :books, type: :has_many
      relation :books, :publishers, type: :belongs_to
  """
  defmacro relation(from, to, opts) do
    quote bind_quoted: [from: from, to: to, opts: opts] do
      type = Keyword.fetch!(opts, :type)
      other = Keyword.delete(opts, :type)

      @caravela_relations %Caravela.Schema.Relation{
        from: from,
        to: to,
        type: type,
        opts: other
      }
    end
  end

  # --- Hooks --------------------------------------------------------------

  @doc """
  Declare a create-time hook for an entity. The hook receives the
  `Ecto.Changeset` and the caller's `context` map, and must return an
  `Ecto.Changeset`.

      on_create :books, fn changeset, _context ->
        Ecto.Changeset.validate_required(changeset, [:title])
      end
  """
  defmacro on_create(entity, fun), do: define_hook(:on_create, entity, fun, __CALLER__)

  @doc """
  Declare an update-time hook. Same shape as `on_create/2`.

      on_update :books, fn changeset, _context ->
        changeset
      end
  """
  defmacro on_update(entity, fun), do: define_hook(:on_update, entity, fun, __CALLER__)

  @doc """
  Declare a delete-time hook. The hook receives the loaded entity and
  the `context`, and must return `:ok` or `{:error, reason}`.

      on_delete :authors, fn author, _context ->
        if author.published?, do: {:error, :has_published_books}, else: :ok
      end
  """
  defmacro on_delete(entity, fun), do: define_hook(:on_delete, entity, fun, __CALLER__)

  # --- Permissions --------------------------------------------------------

  @doc """
  Filter a read query by authorization context. Must return an
  `Ecto.Query`.

      can_read :books, fn query, context ->
        case context.current_user.role do
          :admin -> query
          _ -> where(query, [b], b.published == true)
        end
      end
  """
  defmacro can_read(entity, fun), do: define_permission(:can_read, entity, fun, __CALLER__)

  @doc """
  Authorize creation of an entity. Receives only the `context` and must
  return a boolean.

      can_create :books, fn context ->
        context.current_user.role in [:admin, :editor]
      end
  """
  defmacro can_create(entity, fun), do: define_permission(:can_create, entity, fun, __CALLER__)

  @doc """
  Authorize updating an entity. Receives the loaded entity and the
  `context`. Must return a boolean.

      can_update :books, fn book, context ->
        context.current_user.role == :admin or book.author_id == context.current_user.author_id
      end
  """
  defmacro can_update(entity, fun), do: define_permission(:can_update, entity, fun, __CALLER__)

  @doc """
  Authorize deletion of an entity. Same shape as `can_update/2`.
  """
  defmacro can_delete(entity, fun), do: define_permission(:can_delete, entity, fun, __CALLER__)

  # --- Internal helpers ---------------------------------------------------

  defp define_hook(action, entity, fun, caller) do
    arity = Map.fetch!(@hook_arity, action)
    validate_fun!(action, fun, arity, caller)

    case action do
      :on_create ->
        quote do
          @caravela_hooks %Caravela.Schema.Hook{
            action: :on_create,
            entity: unquote(entity),
            arity: 2
          }

          def __caravela_hook__(:on_create, unquote(entity), changeset, context) do
            unquote(fun).(changeset, context)
          end
        end

      :on_update ->
        quote do
          @caravela_hooks %Caravela.Schema.Hook{
            action: :on_update,
            entity: unquote(entity),
            arity: 2
          }

          def __caravela_hook__(:on_update, unquote(entity), changeset, context) do
            unquote(fun).(changeset, context)
          end
        end

      :on_delete ->
        quote do
          @caravela_hooks %Caravela.Schema.Hook{
            action: :on_delete,
            entity: unquote(entity),
            arity: 2
          }

          def __caravela_hook__(:on_delete, unquote(entity), entity_value, context) do
            unquote(fun).(entity_value, context)
          end
        end
    end
  end

  defp define_permission(action, entity, fun, caller) do
    arity = Map.fetch!(@permission_arity, action)
    validate_fun!(action, fun, arity, caller)

    case action do
      :can_read ->
        quote do
          @caravela_permissions %Caravela.Schema.Permission{
            action: :can_read,
            entity: unquote(entity),
            arity: 2
          }

          def __caravela_permission__(:can_read, unquote(entity), query, context) do
            unquote(fun).(query, context)
          end
        end

      :can_create ->
        quote do
          @caravela_permissions %Caravela.Schema.Permission{
            action: :can_create,
            entity: unquote(entity),
            arity: 1
          }

          def __caravela_permission__(:can_create, unquote(entity), context) do
            unquote(fun).(context)
          end
        end

      :can_update ->
        quote do
          @caravela_permissions %Caravela.Schema.Permission{
            action: :can_update,
            entity: unquote(entity),
            arity: 2
          }

          def __caravela_permission__(:can_update, unquote(entity), entity_value, context) do
            unquote(fun).(entity_value, context)
          end
        end

      :can_delete ->
        quote do
          @caravela_permissions %Caravela.Schema.Permission{
            action: :can_delete,
            entity: unquote(entity),
            arity: 2
          }

          def __caravela_permission__(:can_delete, unquote(entity), entity_value, context) do
            unquote(fun).(entity_value, context)
          end
        end
    end
  end

  # Inspect the quoted fun AST to enforce arity at compile time. Accepts
  # `fn a, b -> ... end`, a captured reference like `&MyMod.my_fun/2`,
  # or `&(&1 + &2)`.
  defp validate_fun!(action, fun, expected, caller) do
    case fun_arity(fun) do
      {:ok, ^expected} ->
        :ok

      {:ok, actual} ->
        compile_error!(
          caller,
          "#{action} expects a function of arity #{expected}, got arity #{actual}"
        )

      :unknown ->
        compile_error!(
          caller,
          "#{action} requires a function literal (fn .. end or &...), got: " <>
            Macro.to_string(fun)
        )
    end
  end

  defp fun_arity({:fn, _, clauses}) when is_list(clauses) do
    arities =
      clauses
      |> Enum.map(fn
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

  # `&Mod.fun/2` or `&fun/2`
  defp fun_arity({:&, _, [{:/, _, [_, arity]}]}) when is_integer(arity), do: {:ok, arity}

  # `&(&1 + &2)` — infer arity from the highest capture placeholder.
  defp fun_arity({:&, _, [body]}) do
    case max_capture(body, 0) do
      0 -> :unknown
      n -> {:ok, n}
    end
  end

  defp fun_arity(_), do: :unknown

  defp max_capture({:&, _, [n]}, acc) when is_integer(n), do: max(acc, n)
  defp max_capture({_, _, args}, acc) when is_list(args), do: max_in_args(args, acc)
  defp max_capture(list, acc) when is_list(list), do: max_in_args(list, acc)
  defp max_capture({a, b}, acc), do: max_capture(b, max_capture(a, acc))
  defp max_capture(_, acc), do: acc

  defp max_in_args(args, acc) do
    Enum.reduce(args, acc, fn arg, a -> max_capture(arg, a) end)
  end

  defp compile_error!(caller, msg) do
    raise CompileError,
      file: Map.get(caller, :file, "unknown"),
      line: Map.get(caller, :line, 0),
      description: "Caravela: " <> msg
  end
end
