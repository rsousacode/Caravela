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

        policy :books do
          scope fn q, actor ->
            if actor.role == :admin, do: q, else: where(q, [b], b.published)
          end

          allow :create, fn actor -> actor.role in [:admin, :editor] end
        end
      end

  After compilation the module exposes `__caravela_domain__/0`, returning
  the validated `Caravela.Schema.Domain` IR, plus `__caravela_hook__/4`
  and the `__caravela_policy_*__` clauses emitted by each `policy` block.
  """

  @hook_actions [:on_create, :on_update, :on_delete]

  # Expected function arity for each action.
  @hook_arity %{on_create: 2, on_update: 2, on_delete: 2}

  @doc false
  def hook_actions, do: @hook_actions
  @doc false
  def hook_arity(action), do: Map.fetch!(@hook_arity, action)

  defmacro __using__(opts) do
    opts = Keyword.update(opts, :default_policy, :deny, & &1)

    unless Keyword.get(opts, :default_policy) in [:deny, :allow] do
      raise Caravela.DSLError,
        message:
          "`use Caravela.Domain, default_policy: …` expects `:deny` or `:allow`, got: " <>
            inspect(Keyword.get(opts, :default_policy)),
        suggestion: "use Caravela.Domain, default_policy: :deny",
        docs_url: "https://hexdocs.pm/caravela/policies.html#default-policy"
    end

    quote do
      # Scoped Ecto.Query helpers so `scope fn q, actor -> where(q, …) end`
      # works without every domain manually importing Ecto.Query. Under
      # `default_policy: :deny` the generated deny-all scope fallback
      # also uses `where/3`.
      import Ecto.Query, only: [where: 3, from: 2]

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
          policy: 2,
          scope: 1,
          allow: 2
        ]

      Module.register_attribute(__MODULE__, :caravela_entities, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_relations, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_hooks, accumulate: true)
      # Raw per-rule accumulator populated by scope/1, field/2 (policy
      # variant), and allow/2 during policy-block expansion. The final
      # `Domain.policies` IR and the specific-rule def clauses are
      # assembled from these tuples in `Caravela.Compiler.__before_compile__`.
      Module.register_attribute(__MODULE__, :caravela_policy_rules, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_domain_opts, persist: false)
      Module.register_attribute(__MODULE__, :caravela_version, persist: false)
      Module.register_attribute(__MODULE__, :caravela_current_fields, persist: false)
      Module.register_attribute(__MODULE__, :caravela_current_auth, persist: false)
      # The policy block's active entity (nil outside of `policy do … end`).
      # scope/1, field/2, and allow/2 read this to know which entity
      # they're declaring rules against.
      Module.register_attribute(__MODULE__, :caravela_current_policy_entity, persist: false)
      @caravela_current_policy_entity nil

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
        raise Caravela.DSLError,
          message: "`version` expects a string, got: #{inspect(v)}",
          suggestion: "version \"v1\"",
          docs_url: "https://hexdocs.pm/caravela/versioning.html"
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
  Declare a field. Two call shapes are supported and dispatched on
  the second argument's AST:

  **Entity field** (inside `entity do … end`): second arg is a type
  atom.

      field :title, :string, required: true, min_length: 3

  **Policy field rule** (inside `policy do … end`): second arg is a
  keyword list with `:visible`.

      field :price, visible: fn actor -> actor.role == :admin end
      field :author_email,
        visible: fn actor, record -> actor.id == record.author_id end

  The dispatch is a pure AST check — no runtime overhead.
  """
  defmacro field(name, second, opts \\ []) do
    if policy_field_ast?(second) do
      define_policy_field(name, second, __CALLER__)
    else
      quote bind_quoted: [name: name, type: second, opts: opts] do
        # If we're inside a `policy` block but the 2nd arg didn't match
        # the `visible: fn …` AST shape (e.g. `field :x, @admin_opts`,
        # which is a module-attribute reference, not a literal kw list),
        # fail with a clear message instead of silently falling through
        # to the entity-field branch.
        if Module.get_attribute(__MODULE__, :caravela_current_policy_entity) do
          raise ArgumentError, """
          `field :#{name}, <opts>` inside a `policy` block must pass a
          literal keyword list with `:visible`, e.g.

              field :#{name}, visible: fn actor -> actor.role == :admin end

          Module-attribute or variable references (e.g. `@admin_opts`)
          aren't supported — the macro needs the fn AST at compile
          time. For shared predicates, either inline them, use a `for`
          comprehension over the field names, or wrap the shape in a
          helper macro that expands to the literal form.
          """
        end

        unless is_atom(name), do: raise(ArgumentError, "field name must be an atom")
        unless is_atom(type), do: raise(ArgumentError, "field type must be an atom")

        entry = %Caravela.Schema.Field{name: name, type: type, opts: opts}
        current = Module.get_attribute(__MODULE__, :caravela_current_fields) || []
        Module.put_attribute(__MODULE__, :caravela_current_fields, [entry | current])
      end
    end
  end

  # True when the 2nd arg AST is a keyword list carrying `:visible` —
  # the shape used by the policy-field variant.
  defp policy_field_ast?(ast) when is_list(ast) do
    Enum.any?(ast, fn
      {:visible, _} -> true
      _ -> false
    end)
  end

  defp policy_field_ast?(_), do: false

  defp define_policy_field(name, opts, caller) do
    fun =
      Keyword.get(opts, :visible) ||
        compile_error!(
          caller,
          "policy `field …, visible: fn …` requires a `visible:` option"
        )

    arity =
      case fun_arity(fun) do
        {:ok, n} when n in [1, 2] ->
          n

        {:ok, n} ->
          compile_error!(
            caller,
            "policy field expects an fn of arity 1 or 2, got arity #{n}"
          )

        :unknown ->
          compile_error!(
            caller,
            "policy field requires a literal fn or capture, got: " <> Macro.to_string(fun)
          )
      end

    # `name` may still be a variable AST at macro-expansion (e.g.
    # `for f <- list, do: field f, visible: …`), so the atom-check
    # runs at emitted-code time.
    quote do
      entity = Module.get_attribute(__MODULE__, :caravela_current_policy_entity)
      name = unquote(name)

      unless entity do
        raise Caravela.DSLError,
          message: "`field :name, visible: …` must be called inside a `policy` block",
          suggestion:
            "policy :books do\n  field :price, visible: fn actor -> actor.role == :admin end\nend",
          docs_url: "https://hexdocs.pm/caravela/policies.html#field-visibility"
      end

      unless is_atom(name) do
        raise Caravela.DSLError,
          message: "policy field name must be an atom, got: #{inspect(name)}",
          suggestion: "field :price, visible: fn actor -> ... end",
          docs_url: "https://hexdocs.pm/caravela/policies.html#field-visibility"
      end

      Module.put_attribute(
        __MODULE__,
        :caravela_policy_rules,
        {:field, entity, name, unquote(arity), unquote(Macro.escape(fun, unquote: true))}
      )
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

  # --- Policies (Phase 9) -------------------------------------------------

  @policy_actions [:create, :update, :delete]

  @doc false
  def policy_actions, do: @policy_actions

  @doc """
  Declare a triple-target policy for `entity`.

      policy :books do
        scope fn query, actor ->
          if actor.role == :admin, do: query, else: where(query, [b], b.published)
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

  The block is plain Elixir — `for`, `if`, helper function calls, and
  `@module_attribute` splicing all work the same as anywhere else:

      policy :books do
        for f <- @admin_only_fields do
          field f, visible: fn actor -> actor.role == :admin end
        end

        if Mix.env() == :dev do
          allow :delete, fn _actor -> true end
        end
      end

  Each rule declaration stores metadata in the `@caravela_policy_rules`
  accumulator; `Caravela.Compiler.__before_compile__/1` then assembles
  the full IR and emits the `__caravela_policy_*__` dispatch clauses
  in one pass.
  """
  defmacro policy(entity, do: block) do
    unless is_atom(entity) do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "Caravela: policy expects an entity atom, got: #{Macro.to_string(entity)}"
    end

    quote do
      prev_entity = Module.get_attribute(__MODULE__, :caravela_current_policy_entity)
      @caravela_current_policy_entity unquote(entity)

      # Record that this entity has a policy block even if no rules
      # are declared — it still qualifies for the per-entity permissive
      # fallback tier in the compiler.
      Module.put_attribute(
        __MODULE__,
        :caravela_policy_rules,
        {:block_declared, unquote(entity)}
      )

      try do
        unquote(block)
      after
        @caravela_current_policy_entity prev_entity
      end
    end
  end

  @doc """
  Declare the row-level scope for the enclosing `policy` block.

      scope fn query, actor ->
        if actor.role == :admin, do: query, else: where(query, [b], b.published)
      end

  The fn must have arity 2 — `(query, actor) -> query`. Raises at
  compile time if called outside a `policy` block.
  """
  defmacro scope(fun) do
    validate_fun!(:scope, fun, 2, __CALLER__)

    quote do
      entity = Module.get_attribute(__MODULE__, :caravela_current_policy_entity)

      unless entity do
        raise Caravela.DSLError,
          message: "`scope` must be called inside a `policy` block",
          suggestion:
            "policy :books do\n  scope fn q, actor -> where(q, [b], b.tenant_id == ^actor.tenant_id) end\nend",
          docs_url: "https://hexdocs.pm/caravela/policies.html#scope"
      end

      Module.put_attribute(
        __MODULE__,
        :caravela_policy_rules,
        {:scope, entity, unquote(Macro.escape(fun, unquote: true))}
      )
    end
  end

  @doc """
  Declare an action gate for the enclosing `policy` block. `action` is
  one of `:create`, `:update`, `:delete`; the fn has arity 1
  (`actor -> bool`) or arity 2 (`actor, record -> bool`).

      allow :create, fn actor -> actor.role in [:admin, :editor] end
      allow :update, fn actor, record -> actor.id == record.author_id end
  """
  defmacro allow(action, fun) do
    unless action in @policy_actions do
      compile_error!(
        __CALLER__,
        "policy allow expects one of #{inspect(@policy_actions)}, got: #{inspect(action)}"
      )
    end

    arity =
      case fun_arity(fun) do
        {:ok, n} when n in [1, 2] ->
          n

        {:ok, n} ->
          compile_error!(
            __CALLER__,
            "policy allow :#{action} expects an fn of arity 1 or 2, got arity #{n}"
          )

        :unknown ->
          compile_error!(
            __CALLER__,
            "policy allow :#{action} requires a literal fn or capture, got: " <>
              Macro.to_string(fun)
          )
      end

    quote do
      entity = Module.get_attribute(__MODULE__, :caravela_current_policy_entity)

      unless entity do
        raise Caravela.DSLError,
          message: "`allow` must be called inside a `policy` block",
          suggestion:
            "policy :books do\n  allow :create, fn actor -> actor.role in [:admin, :editor] end\nend",
          docs_url: "https://hexdocs.pm/caravela/policies.html#allow"
      end

      Module.put_attribute(
        __MODULE__,
        :caravela_policy_rules,
        {:allow, entity, unquote(action), unquote(arity),
         unquote(Macro.escape(fun, unquote: true))}
      )
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
          raise Caravela.DSLError,
            message: "`authenticatable/1` must be called inside an `entity do … end` block",
            suggestion:
              "entity :users do\n  field :email, :string, required: true\n  authenticatable do\n    strategy :password\n  end\nend",
            docs_url: "https://hexdocs.pm/caravela/auth.html"
      end
    end
  end

  @doc "Declare a credential strategy inside an `authenticatable` block."
  defmacro strategy(name, opts \\ []) do
    quote bind_quoted: [name: name, opts: opts] do
      unless name in [:password, :api_token] do
        raise Caravela.DSLError,
          message:
            "unknown auth strategy #{inspect(name)} — expected `:password` or `:api_token`",
          suggestion: "strategy :password, hashing: :argon2",
          docs_url: "https://hexdocs.pm/caravela/auth.html#strategies"
      end

      {ename, cfg} = Module.get_attribute(__MODULE__, :caravela_current_auth)

      unless match?(%Caravela.Schema.AuthConfig{}, cfg) do
        raise Caravela.DSLError,
          message: "`strategy/2` must be called inside an `authenticatable do … end` block",
          suggestion:
            "entity :users do\n  authenticatable do\n    strategy :password, hashing: :argon2\n  end\nend",
          docs_url: "https://hexdocs.pm/caravela/auth.html#strategies"
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
        raise Caravela.DSLError,
          message: "`session/2` must be called inside an `authenticatable do … end` block",
          suggestion:
            "authenticatable do\n  strategy :password\n  session :token, ttl: {30, :days}\nend",
          docs_url: "https://hexdocs.pm/caravela/auth.html#session"
      end

      @caravela_current_auth {ename, %{cfg | session: opts}}
    end
  end

  @doc "Enable email confirmation inside an `authenticatable` block."
  defmacro confirm(_kind, opts \\ []) do
    quote bind_quoted: [opts: opts] do
      {ename, cfg} = Module.get_attribute(__MODULE__, :caravela_current_auth)

      unless match?(%Caravela.Schema.AuthConfig{}, cfg) do
        raise Caravela.DSLError,
          message: "`confirm/2` must be called inside an `authenticatable do … end` block",
          suggestion:
            "authenticatable do\n  strategy :password\n  confirm :email, token_ttl: {24, :hours}\nend",
          docs_url: "https://hexdocs.pm/caravela/auth.html#email-confirmation"
      end

      @caravela_current_auth {ename, %{cfg | confirm: opts}}
    end
  end

  @doc "Enable password reset inside an `authenticatable` block."
  defmacro reset(_kind, opts \\ []) do
    quote bind_quoted: [opts: opts] do
      {ename, cfg} = Module.get_attribute(__MODULE__, :caravela_current_auth)

      unless match?(%Caravela.Schema.AuthConfig{}, cfg) do
        raise Caravela.DSLError,
          message: "`reset/2` must be called inside an `authenticatable do … end` block",
          suggestion:
            "authenticatable do\n  strategy :password\n  reset :password, token_ttl: {1, :hour}\nend",
          docs_url: "https://hexdocs.pm/caravela/auth.html#password-reset"
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
        raise Caravela.DSLError,
          message:
            "`#{unquote(action)}/1` must be called inside an `authenticatable do … end` block",
          suggestion:
            "authenticatable do\n  strategy :password\n  #{unquote(action)} fn changeset, _ctx -> changeset end\nend",
          docs_url: "https://hexdocs.pm/caravela/auth.html#hooks"
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
