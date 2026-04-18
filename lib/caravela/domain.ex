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
          version: 1,
          on_create: 2,
          on_update: 2,
          on_delete: 2,
          can_read: 2,
          can_create: 2,
          can_update: 2,
          can_delete: 2,
          authenticatable: 1,
          strategy: 1,
          strategy: 2,
          session: 1,
          session: 2,
          confirm: 1,
          confirm: 2,
          reset: 1,
          reset: 2,
          on_register: 1,
          on_login: 1,
          policy: 2
        ]

      Module.register_attribute(__MODULE__, :caravela_entities, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_relations, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_hooks, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_permissions, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_policies, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_domain_opts, persist: false)
      Module.register_attribute(__MODULE__, :caravela_version, persist: false)
      Module.register_attribute(__MODULE__, :caravela_current_fields, persist: false)
      Module.register_attribute(__MODULE__, :caravela_current_auth, persist: false)

      @caravela_domain_opts unquote(opts)
      @caravela_version nil
      @before_compile Caravela.Compiler
    end
  end

  @doc """
  Declare the API version for this domain. Must match `~r/^v\\d+$/`.

      version "v1"

  When set, all generated modules are namespaced under the version
  (`MyApp.Library.V1.Book`) and controller routes are prefixed with
  `/api/v1/`.
  """
  defmacro version(v) do
    quote bind_quoted: [v: v] do
      unless is_binary(v) do
        raise ArgumentError, "version must be a string like \"v1\", got: #{inspect(v)}"
      end

      @caravela_version v
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
      @caravela_current_auth {unquote(name), nil}
      unquote(block)
      fields = Enum.reverse(Module.get_attribute(__MODULE__, :caravela_current_fields))

      auth =
        case Module.get_attribute(__MODULE__, :caravela_current_auth) do
          {_ename, nil} -> nil
          {_ename, %Caravela.Schema.AuthConfig{} = cfg} -> cfg
        end

      @caravela_entities %Caravela.Schema.Entity{
        name: unquote(name),
        fields: fields,
        auth: auth
      }

      Module.delete_attribute(__MODULE__, :caravela_current_fields)
      Module.delete_attribute(__MODULE__, :caravela_current_auth)
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

  # --- Policies (Phase 9) -------------------------------------------------

  @policy_actions [:create, :update, :delete]

  @doc false
  def policy_actions, do: @policy_actions

  @doc """
  Declare a triple-target policy for `entity`.

      policy :books do
        scope fn query, actor ->
          case actor.role do
            :admin -> query
            _ -> where(query, [b], b.published == true)
          end
        end

        field :internal_notes, visible: fn actor -> actor.role == :admin end
        field :author_email,   visible: fn actor, record ->
          actor.role == :admin or actor.id == record.author_id
        end

        allow :create, fn actor -> actor.role in [:admin, :editor] end
        allow :update, fn actor, record ->
          actor.role == :admin or actor.id == record.author_id
        end
        allow :delete, fn actor -> actor.role == :admin end
      end

  Each declared rule compiles into a clause of one of three dispatch
  functions on the domain module:

    * `__caravela_policy_scope__/3`          — `(entity, query, actor)`
    * `__caravela_policy_field_visible__/3`  — `(entity, field, actor)`
    * `__caravela_policy_field_visible__/4`  — `(entity, field, actor, record)`
    * `__caravela_policy_allow__/3`          — `(entity, action, actor)`
    * `__caravela_policy_allow__/4`          — `(entity, action, actor, record)`

  The generated context, controller, GraphQL resolvers, and LiveView
  modules then invoke these to produce (1) Ecto WHERE clauses, (2)
  projected JSON responses with invisible fields removed, and (3) a
  typed `field_access` prop flowing to Svelte components.
  """
  defmacro policy(entity, do: block) do
    unless is_atom(entity) do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "Caravela: policy expects an entity atom, got: #{Macro.to_string(entity)}"
    end

    {clauses, field_rules, action_gates, has_scope?} =
      compile_policy_block(block, entity, __CALLER__)

    entry =
      Macro.escape(%Caravela.Policy.Entry{
        entity: entity,
        has_scope?: has_scope?,
        fields: field_rules,
        actions: action_gates
      })

    quote do
      @caravela_policies unquote(entry)
      unquote_splicing(clauses)
    end
  end

  # Walk the AST of a `policy do ... end` block, emitting per-directive
  # def clauses and gathering IR metadata.
  defp compile_policy_block(block, entity, caller) do
    statements =
      case block do
        {:__block__, _, stmts} -> stmts
        nil -> []
        single -> [single]
      end

    Enum.reduce(statements, {[], [], [], false}, fn stmt, acc ->
      compile_policy_stmt(stmt, entity, caller, acc)
    end)
  end

  defp compile_policy_stmt({:scope, _meta, [fun]}, entity, caller, {cls, fields, actions, _had?}) do
    validate_fun!(:scope, fun, 2, caller)

    clause =
      quote do
        def __caravela_policy_scope__(unquote(entity), query, actor) do
          unquote(fun).(query, actor)
        end
      end

    {cls ++ [clause], fields, actions, true}
  end

  defp compile_policy_stmt(
         {:field, _meta, [fname, [{:visible, fun} | _rest]]},
         entity,
         caller,
         {cls, fields, actions, had?}
       ) do
    unless is_atom(fname) do
      compile_error!(caller, "policy field name must be an atom, got: #{Macro.to_string(fname)}")
    end

    arity =
      case fun_arity(fun) do
        {:ok, n} when n in [1, 2] ->
          n

        {:ok, n} ->
          compile_error!(
            caller,
            "policy field :#{fname} expects an fn of arity 1 or 2, got arity #{n}"
          )

        :unknown ->
          compile_error!(
            caller,
            "policy field :#{fname} requires a literal fn or capture, got: " <>
              Macro.to_string(fun)
          )
      end

    clause = policy_field_clause(entity, fname, fun, arity)
    rule = %Caravela.Policy.FieldRule{entity: entity, field: fname, arity: arity}
    {cls ++ [clause], fields ++ [rule], actions, had?}
  end

  defp compile_policy_stmt(
         {:allow, _meta, [action, fun]},
         entity,
         caller,
         {cls, fields, actions, had?}
       ) do
    unless action in @policy_actions do
      compile_error!(
        caller,
        "policy allow expects one of #{inspect(@policy_actions)}, got: #{inspect(action)}"
      )
    end

    arity =
      case fun_arity(fun) do
        {:ok, n} when n in [1, 2] ->
          n

        {:ok, n} ->
          compile_error!(
            caller,
            "policy allow :#{action} expects an fn of arity 1 or 2, got arity #{n}"
          )

        :unknown ->
          compile_error!(
            caller,
            "policy allow :#{action} requires a literal fn or capture, got: " <>
              Macro.to_string(fun)
          )
      end

    clause = policy_allow_clause(entity, action, fun, arity)
    gate = %Caravela.Policy.ActionGate{entity: entity, action: action, arity: arity}
    {cls ++ [clause], fields, actions ++ [gate], had?}
  end

  defp compile_policy_stmt(other, _entity, caller, _acc) do
    compile_error!(
      caller,
      "unsupported directive in `policy` block: #{Macro.to_string(other)}. " <>
        "Expected `scope fn -> ... end`, `field :name, visible: fn -> ... end`, " <>
        "or `allow :action, fn -> ... end`."
    )
  end

  defp policy_field_clause(entity, fname, fun, 1) do
    quote do
      def __caravela_policy_field_visible__(unquote(entity), unquote(fname), actor) do
        unquote(fun).(actor)
      end

      def __caravela_policy_field_visible__(
            unquote(entity),
            unquote(fname),
            actor,
            _record
          ) do
        unquote(fun).(actor)
      end
    end
  end

  defp policy_field_clause(entity, fname, fun, 2) do
    quote do
      def __caravela_policy_field_visible__(unquote(entity), unquote(fname), _actor) do
        # Arity-2 rules depend on the record; without one they're
        # flagged :per_record so the caller knows to evaluate per row.
        :per_record
      end

      def __caravela_policy_field_visible__(
            unquote(entity),
            unquote(fname),
            actor,
            record
          ) do
        unquote(fun).(actor, record)
      end
    end
  end

  defp policy_allow_clause(entity, action, fun, 1) do
    quote do
      def __caravela_policy_allow__(unquote(entity), unquote(action), actor) do
        unquote(fun).(actor)
      end

      def __caravela_policy_allow__(unquote(entity), unquote(action), actor, _record) do
        unquote(fun).(actor)
      end
    end
  end

  defp policy_allow_clause(entity, action, fun, 2) do
    quote do
      def __caravela_policy_allow__(unquote(entity), unquote(action), actor) do
        # Arity-2 gate without a record defaults to denying — the
        # caller should pass the record for a real decision.
        _ = actor
        false
      end

      def __caravela_policy_allow__(unquote(entity), unquote(action), actor, record) do
        unquote(fun).(actor, record)
      end
    end
  end

  # --- Authentication (Phase 7) ------------------------------------------

  @auth_hook_actions [:on_register, :on_login]
  @auth_hook_arity %{on_register: 2, on_login: 2}

  @doc false
  def auth_hook_actions, do: @auth_hook_actions

  @doc """
  Declare the `authenticatable` trait on the enclosing `entity`.

      entity :users do
        field :email, :string, required: true, unique: true
        field :name, :string, required: true

        authenticatable do
          strategy :password
          strategy :api_token, scopes: [:read, :write], ttl: {90, :days}
          session :token, ttl: {30, :days}, remember_me: {365, :days}
          confirm :email, token_ttl: {24, :hours}
          reset :password, token_ttl: {1, :hour}

          on_register fn changeset, _ctx -> changeset end
          on_login fn user, _ctx ->
            if user.suspended, do: {:error, :suspended}, else: :ok
          end
        end
      end

  See `Caravela.Schema.AuthConfig` for the parsed IR.
  """
  defmacro authenticatable(do: block) do
    quote do
      case Module.get_attribute(__MODULE__, :caravela_current_auth) do
        {ename, _} ->
          @caravela_current_auth {ename, %Caravela.Schema.AuthConfig{}}
          unquote(block)

        _ ->
          raise ArgumentError,
                "authenticatable/1 must be called inside an entity do .. end block"
      end
    end
  end

  @doc "Declare a credential strategy inside an `authenticatable` block."
  defmacro strategy(name, opts \\ []) do
    quote bind_quoted: [name: name, opts: opts] do
      unless name in [:password, :api_token] do
        raise ArgumentError,
              "unknown auth strategy #{inspect(name)} — expected :password or :api_token"
      end

      {ename, cfg} = Module.get_attribute(__MODULE__, :caravela_current_auth)

      unless match?(%Caravela.Schema.AuthConfig{}, cfg) do
        raise ArgumentError, "strategy/2 must be called inside an authenticatable do .. end block"
      end

      strategies = cfg.strategies ++ [{name, opts}]
      @caravela_current_auth {ename, %{cfg | strategies: strategies}}
    end
  end

  @doc "Configure session management inside an `authenticatable` block."
  defmacro session(_kind, opts \\ []) do
    quote bind_quoted: [opts: opts] do
      {ename, cfg} = Module.get_attribute(__MODULE__, :caravela_current_auth)

      unless match?(%Caravela.Schema.AuthConfig{}, cfg) do
        raise ArgumentError, "session/2 must be called inside an authenticatable do .. end block"
      end

      @caravela_current_auth {ename, %{cfg | session: opts}}
    end
  end

  @doc "Enable email confirmation inside an `authenticatable` block."
  defmacro confirm(_kind, opts \\ []) do
    quote bind_quoted: [opts: opts] do
      {ename, cfg} = Module.get_attribute(__MODULE__, :caravela_current_auth)

      unless match?(%Caravela.Schema.AuthConfig{}, cfg) do
        raise ArgumentError, "confirm/2 must be called inside an authenticatable do .. end block"
      end

      @caravela_current_auth {ename, %{cfg | confirm: opts}}
    end
  end

  @doc "Enable password reset inside an `authenticatable` block."
  defmacro reset(_kind, opts \\ []) do
    quote bind_quoted: [opts: opts] do
      {ename, cfg} = Module.get_attribute(__MODULE__, :caravela_current_auth)

      unless match?(%Caravela.Schema.AuthConfig{}, cfg) do
        raise ArgumentError, "reset/2 must be called inside an authenticatable do .. end block"
      end

      @caravela_current_auth {ename, %{cfg | reset: opts}}
    end
  end

  @doc """
  Custom registration logic. Receives the changeset and the caller's
  context map, returns the changeset.
  """
  defmacro on_register(fun), do: define_auth_hook(:on_register, fun, __CALLER__)

  @doc """
  Custom post-login logic. Receives the loaded user and the caller's
  context, returns `:ok` or `{:error, reason}`.
  """
  defmacro on_login(fun), do: define_auth_hook(:on_login, fun, __CALLER__)

  defp define_auth_hook(action, fun, caller) do
    arity = Map.fetch!(@auth_hook_arity, action)
    validate_fun!(action, fun, arity, caller)

    mark =
      case action do
        :on_register -> quote do: %{cfg | on_register?: true}
        :on_login -> quote do: %{cfg | on_login?: true}
      end

    hook_body =
      case action do
        :on_register ->
          quote do
            def __caravela_auth_hook__(:on_register, changeset, context) do
              unquote(fun).(changeset, context)
            end
          end

        :on_login ->
          quote do
            def __caravela_auth_hook__(:on_login, user, context) do
              unquote(fun).(user, context)
            end
          end
      end

    quote do
      {ename, cfg} = Module.get_attribute(__MODULE__, :caravela_current_auth)

      unless match?(%Caravela.Schema.AuthConfig{}, cfg) do
        raise ArgumentError,
              "#{unquote(action)}/1 must be called inside an authenticatable do .. end block"
      end

      @caravela_current_auth {ename, unquote(mark)}

      unquote(hook_body)
    end
  end

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
