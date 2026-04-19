defmodule Caravela.Compiler do
  @moduledoc """
  Compile-time hook that assembles and validates a domain IR.

  Wired up via `@before_compile Caravela.Compiler` from modules that
  `use Caravela.Domain`.
  """

  alias Caravela.Schema.{AuthConfig, Domain, Entity, Field, Relation, Hook}
  alias Caravela.{Auth, Tenant, Types}

  @relation_types ~w(has_many has_one belongs_to many_to_many)a
  @version_re ~r/^v\d+$/

  defmacro __before_compile__(env) do
    entities = env.module |> Module.get_attribute(:caravela_entities) |> Enum.reverse()
    relations = env.module |> Module.get_attribute(:caravela_relations) |> Enum.reverse()
    hooks = env.module |> Module.get_attribute(:caravela_hooks) |> Enum.reverse()

    # Raw per-rule tuples pushed by `scope/1`, `field/2` (policy), and
    # `allow/2` during the `policy` block. The attribute accumulates
    # newest-first, so reverse before building the IR so user order is
    # preserved.
    policy_rules = env.module |> Module.get_attribute(:caravela_policy_rules) |> Enum.reverse()
    policies = build_policy_entries(policy_rules)

    raw_opts = Module.get_attribute(env.module, :caravela_domain_opts) || []
    version = Module.get_attribute(env.module, :caravela_version)

    opts =
      case version do
        nil -> raw_opts
        v when is_binary(v) -> Keyword.put(raw_opts, :version, v)
      end

    domain = %Domain{
      module: env.module,
      entities: entities,
      relations: relations,
      hooks: hooks,
      policies: policies,
      opts: opts
    }

    :ok = validate!(domain, env)
    domain = domain |> Tenant.inject() |> Auth.inject()

    Module.put_attribute(env.module, :caravela_domain_compiled, domain)

    specific_policy_clauses = specific_policy_clauses(policy_rules)
    per_entity_policy_fallbacks = per_entity_policy_fallbacks(domain)
    module_level_policy_fallbacks = module_level_policy_fallbacks(domain)

    quote do
      @doc false
      def __caravela_domain__ do
        @caravela_domain_compiled
      end

      # Fallbacks. Must come after the specific clauses emitted by each
      # on_* macro.
      @doc false
      def __caravela_hook__(:on_create, _entity, changeset, _context), do: changeset
      def __caravela_hook__(:on_update, _entity, changeset, _context), do: changeset
      def __caravela_hook__(:on_delete, _entity, _entity_value, _context), do: :ok

      @doc false
      def __caravela_auth_hook__(:on_register, changeset, _context), do: changeset
      def __caravela_auth_hook__(:on_login, _user, _context), do: :ok

      # --- Policy dispatch clauses (Phase 9) -----------------------------
      #
      # Clause ordering matters. In order:
      #
      #   1. Specific clauses — one per `scope`, `field :_, visible: …`,
      #      or `allow :_, …` declared in a `policy` block.
      #   2. Per-entity permissive fallbacks — for each entity that
      #      declared ANY policy block, undeclared rule types default
      #      to "permissive for this entity" regardless of the
      #      domain-level default.
      #   3. Module-level fallbacks — governed by the `default_policy`
      #      domain option. Only fires for entities with no `policy`
      #      block at all.
      unquote_splicing(specific_policy_clauses)
      unquote_splicing(per_entity_policy_fallbacks)
      unquote_splicing(module_level_policy_fallbacks)
    end
  end

  # Build the IR from raw rule tuples. Each `policy :entity do … end`
  # block pushes a `{:block_declared, entity}` marker plus one tuple
  # per `scope` / `field` / `allow` call. We group by entity here.
  defp build_policy_entries(rules) do
    rules
    |> Enum.reduce(%{}, fn
      {:block_declared, entity}, acc ->
        Map.put_new(acc, entity, new_entry(entity))

      {:scope, entity, _fun_ast}, acc ->
        entry = Map.get(acc, entity, new_entry(entity))

        if entry.has_scope? do
          raise Caravela.DSLError,
            message: "duplicate policy scope rule for #{inspect(entity)}",
            suggestion:
              "each entity may declare at most one `scope fn q, actor -> ... end`.\n" <>
                "Remove the extra `scope` call, or combine the two into one fn.",
            docs_url: "https://hexdocs.pm/caravela/policies.html#scope"
        end

        Map.put(acc, entity, %{entry | has_scope?: true})

      {:field, entity, fname, arity, _fun_ast}, acc ->
        entry = Map.get(acc, entity, new_entry(entity))
        rule = %Caravela.Policy.FieldRule{entity: entity, field: fname, arity: arity}
        Map.put(acc, entity, %{entry | fields: entry.fields ++ [rule]})

      {:allow, entity, action, arity, _fun_ast}, acc ->
        entry = Map.get(acc, entity, new_entry(entity))
        gate = %Caravela.Policy.ActionGate{entity: entity, action: action, arity: arity}
        Map.put(acc, entity, %{entry | actions: entry.actions ++ [gate]})
    end)
    |> Map.values()
  end

  defp new_entry(entity) do
    %Caravela.Policy.Entry{entity: entity, has_scope?: false, fields: [], actions: []}
  end

  # Emit one-or-more `def __caravela_policy_*__(…)` clauses per raw
  # rule. The AST of each user-supplied fn was stored escaped in the
  # module attribute; unquoting it inserts the literal fn back into
  # the generated def.
  defp specific_policy_clauses(rules) do
    Enum.flat_map(rules, fn
      {:block_declared, _entity} ->
        []

      {:scope, entity, fun_ast} ->
        [
          quote do
            def __caravela_policy_scope__(unquote(entity), query, actor) do
              unquote(fun_ast).(query, actor)
            end
          end
        ]

      {:field, entity, fname, 1, fun_ast} ->
        [
          quote do
            def __caravela_policy_field_visible__(unquote(entity), unquote(fname), actor) do
              unquote(fun_ast).(actor)
            end
          end,
          quote do
            def __caravela_policy_field_visible__(
                  unquote(entity),
                  unquote(fname),
                  actor,
                  _record
                ) do
              unquote(fun_ast).(actor)
            end
          end
        ]

      {:field, entity, fname, 2, fun_ast} ->
        [
          quote do
            # Arity-2 rules depend on the record; without one they're
            # flagged :per_record so the caller knows to evaluate per row.
            def __caravela_policy_field_visible__(unquote(entity), unquote(fname), _actor),
              do: :per_record
          end,
          quote do
            def __caravela_policy_field_visible__(
                  unquote(entity),
                  unquote(fname),
                  actor,
                  record
                ) do
              unquote(fun_ast).(actor, record)
            end
          end
        ]

      {:allow, entity, action, 1, fun_ast} ->
        [
          quote do
            def __caravela_policy_allow__(unquote(entity), unquote(action), actor) do
              unquote(fun_ast).(actor)
            end
          end,
          quote do
            def __caravela_policy_allow__(unquote(entity), unquote(action), actor, _record) do
              unquote(fun_ast).(actor)
            end
          end
        ]

      {:allow, entity, action, 2, fun_ast} ->
        [
          quote do
            # Arity-2 gate without a record defaults to denying — the
            # caller should pass the record for a real decision.
            def __caravela_policy_allow__(unquote(entity), unquote(action), _actor), do: false
          end,
          quote do
            def __caravela_policy_allow__(unquote(entity), unquote(action), actor, record) do
              unquote(fun_ast).(actor, record)
            end
          end
        ]
    end)
  end

  # For each entity with a declared policy, emit a permissive fallback
  # covering undeclared rule types. These sit between the specific
  # per-rule clauses and the module-level default.
  defp per_entity_policy_fallbacks(%Domain{policies: policies}) do
    policies
    |> Enum.flat_map(fn %{entity: entity} ->
      [
        quote do
          def __caravela_policy_scope__(unquote(entity), query, _actor), do: query
        end,
        quote do
          def __caravela_policy_field_visible__(unquote(entity), _field, _actor), do: true
        end,
        quote do
          def __caravela_policy_field_visible__(
                unquote(entity),
                _field,
                _actor,
                _record
              ),
              do: true
        end,
        quote do
          def __caravela_policy_allow__(unquote(entity), _action, _actor), do: true
        end,
        quote do
          def __caravela_policy_allow__(unquote(entity), _action, _actor, _record),
            do: true
        end
      ]
    end)
  end

  defp module_level_policy_fallbacks(%Domain{} = domain) do
    case Domain.default_policy(domain) do
      :deny -> deny_fallbacks()
      :allow -> allow_fallbacks()
    end
  end

  defp allow_fallbacks do
    [
      quote do
        def __caravela_policy_scope__(_entity, query, _actor), do: query
      end,
      quote do
        def __caravela_policy_field_visible__(_entity, _field, _actor), do: true
      end,
      quote do
        def __caravela_policy_field_visible__(_entity, _field, _actor, _record), do: true
      end,
      quote do
        def __caravela_policy_allow__(_entity, _action, _actor), do: true
      end,
      quote do
        def __caravela_policy_allow__(_entity, _action, _actor, _record), do: true
      end
    ]
  end

  defp deny_fallbacks do
    [
      quote do
        # Deny-all scope: force zero rows via `WHERE false`. `where/3`
        # is imported in `use Caravela.Domain`, so it resolves here.
        def __caravela_policy_scope__(_entity, query, _actor) do
          where(query, [_q], false)
        end
      end,
      quote do
        def __caravela_policy_field_visible__(_entity, _field, _actor), do: false
      end,
      quote do
        def __caravela_policy_field_visible__(_entity, _field, _actor, _record), do: false
      end,
      quote do
        def __caravela_policy_allow__(_entity, _action, _actor), do: false
      end,
      quote do
        def __caravela_policy_allow__(_entity, _action, _actor, _record), do: false
      end
    ]
  end

  @doc """
  Runs all validations on a compiled `Caravela.Schema.Domain`.

  Raises `CompileError` with a descriptive message on the first failure.
  """
  def validate!(%Domain{} = domain, env \\ %{file: "unknown", line: 0}) do
    with :ok <- validate_version(domain, env),
         :ok <- validate_tenant_field_collision(domain, env),
         :ok <- validate_unique_entities(domain, env),
         :ok <- validate_field_types(domain, env),
         :ok <- validate_field_constraints(domain, env),
         :ok <- validate_relation_types(domain, env),
         :ok <- validate_referential_integrity(domain, env),
         :ok <- validate_cardinality(domain, env),
         :ok <- validate_no_circular_required(domain, env),
         :ok <- validate_hook_entities(domain, env),
         :ok <- validate_unique_hooks(domain, env),
         :ok <- validate_auth(domain, env),
         :ok <- validate_policies(domain, env) do
      :ok
    end
  end

  defp validate_version(%Domain{} = domain, env) do
    case Domain.version(domain) do
      nil ->
        :ok

      v when is_binary(v) ->
        if Regex.match?(@version_re, v) do
          :ok
        else
          compile_error!(
            env,
            "version #{inspect(v)} is invalid — must match #{inspect(@version_re)} (e.g. \"v1\")"
          )
        end

      other ->
        compile_error!(env, "version must be a string like \"v1\", got: #{inspect(other)}")
    end
  end

  defp validate_tenant_field_collision(%Domain{} = domain, env) do
    if Domain.multi_tenant?(domain) do
      Enum.each(domain.entities, fn %Entity{name: ename, fields: fs} ->
        if Enum.any?(fs, &(&1.name == Caravela.Tenant.field_name())) do
          compile_error!(
            env,
            "entity #{inspect(ename)} declares a :tenant_id field, but the domain " <>
              "has multi_tenant: true — tenant_id is auto-injected. Remove the manual field."
          )
        end
      end)
    end

    :ok
  end

  # --- validations --------------------------------------------------------

  defp validate_unique_entities(%Domain{entities: es}, env) do
    names = Enum.map(es, & &1.name)

    case names -- Enum.uniq(names) do
      [] -> :ok
      [dup | _] -> compile_error!(env, "duplicate entity #{inspect(dup)}")
    end
  end

  defp validate_field_types(%Domain{entities: es}, env) do
    Enum.each(es, fn %Entity{name: ename, fields: fields} ->
      Enum.each(fields, fn %Field{name: fname, type: ftype} ->
        unless Types.known?(ftype) do
          compile_error!(
            env,
            "unknown field type #{inspect(ftype)} on #{ename}.#{fname} " <>
              "(known types: #{inspect(Types.known_types())})"
          )
        end
      end)
    end)

    :ok
  end

  defp validate_field_constraints(%Domain{entities: es}, env) do
    numeric_only = [:min, :max, :precision, :scale]
    string_only = [:min_length, :max_length, :format]

    Enum.each(es, fn %Entity{name: ename, fields: fields} ->
      Enum.each(fields, fn %Field{name: fname, type: ftype, opts: opts} ->
        opts = opts || []

        if not Types.numeric?(ftype) do
          case Enum.find(numeric_only, &Keyword.has_key?(opts, &1)) do
            nil ->
              :ok

            offending ->
              compile_error!(
                env,
                "field #{ename}.#{fname} has numeric option #{inspect(offending)} " <>
                  "but type #{inspect(ftype)} is not numeric"
              )
          end
        end

        if not Types.string_like?(ftype) do
          case Enum.find(string_only, &Keyword.has_key?(opts, &1)) do
            nil ->
              :ok

            offending ->
              compile_error!(
                env,
                "field #{ename}.#{fname} has string option #{inspect(offending)} " <>
                  "but type #{inspect(ftype)} is not a string"
              )
          end
        end
      end)
    end)

    :ok
  end

  defp validate_relation_types(%Domain{relations: rels}, env) do
    Enum.each(rels, fn %Relation{from: f, to: t, type: type} ->
      unless type in @relation_types do
        compile_error!(
          env,
          "invalid relation type #{inspect(type)} between #{f} and #{t}; " <>
            "must be one of #{inspect(@relation_types)}"
        )
      end
    end)

    :ok
  end

  defp validate_referential_integrity(%Domain{entities: es, relations: rels}, env) do
    names = MapSet.new(es, & &1.name)

    Enum.each(rels, fn %Relation{from: f, to: t} ->
      unless MapSet.member?(names, f) do
        compile_error!(env, "relation references unknown entity #{inspect(f)}")
      end

      unless MapSet.member?(names, t) do
        compile_error!(env, "relation references unknown entity #{inspect(t)}")
      end
    end)

    :ok
  end

  # If both sides of a relation are declared, they must be compatible. The
  # opposite side can be omitted — the generators will infer it.
  defp validate_cardinality(%Domain{relations: rels}, env) do
    by_pair = Enum.reduce(rels, %{}, fn r, acc -> Map.put(acc, {r.from, r.to}, r.type) end)

    Enum.each(rels, fn %Relation{from: f, to: t, type: type} = rel ->
      case Map.get(by_pair, {t, f}) do
        nil ->
          :ok

        reverse ->
          unless compatible_pair?(type, reverse) do
            compile_error!(
              env,
              "incompatible cardinality between #{rel.from} and #{rel.to}: " <>
                "#{type} vs #{reverse}"
            )
          end
      end
    end)

    :ok
  end

  defp compatible_pair?(:has_many, :belongs_to), do: true
  defp compatible_pair?(:has_one, :belongs_to), do: true
  defp compatible_pair?(:belongs_to, :has_many), do: true
  defp compatible_pair?(:belongs_to, :has_one), do: true
  defp compatible_pair?(:many_to_many, :many_to_many), do: true
  defp compatible_pair?(_, _), do: false

  # A required belongs_to from A -> B is an edge. A cycle in that graph is
  # unsatisfiable: you could never insert a row without its FK targets
  # existing, so creating the first row of any entity in the cycle is impossible.
  defp validate_no_circular_required(%Domain{relations: rels}, env) do
    edges =
      for %Relation{from: f, to: t, type: :belongs_to, opts: opts} <- rels,
          Keyword.get(opts, :required, false) do
        {f, t}
      end

    graph =
      Enum.reduce(edges, %{}, fn {a, b}, acc ->
        Map.update(acc, a, [b], &[b | &1])
      end)

    Enum.each(Map.keys(graph), fn node ->
      case find_cycle(graph, node, [node]) do
        nil -> :ok
        path -> compile_error!(env, "circular required belongs_to chain: #{inspect(path)}")
      end
    end)

    :ok
  end

  defp find_cycle(graph, current, path) do
    Enum.reduce_while(Map.get(graph, current, []), nil, fn next, _acc ->
      cond do
        next in path ->
          {:halt, Enum.reverse([next | path])}

        true ->
          case find_cycle(graph, next, [next | path]) do
            nil -> {:cont, nil}
            cycle -> {:halt, cycle}
          end
      end
    end)
  end

  defp validate_hook_entities(%Domain{entities: es, hooks: hooks}, env) do
    names = MapSet.new(es, & &1.name)

    Enum.each(hooks, fn %Hook{action: a, entity: e} ->
      unless MapSet.member?(names, e) do
        compile_error!(env, "hook #{a} references unknown entity #{inspect(e)}")
      end
    end)

    :ok
  end

  defp validate_unique_hooks(%Domain{hooks: hooks}, env) do
    pairs = Enum.map(hooks, &{&1.action, &1.entity})

    case pairs -- Enum.uniq(pairs) do
      [] ->
        :ok

      [{a, e} | _] ->
        compile_error!(env, "duplicate hook #{a} for entity #{inspect(e)}")
    end
  end

  defp validate_auth(%Domain{entities: es}, env) do
    auth_entities = Enum.filter(es, fn %Entity{auth: a} -> not is_nil(a) end)

    with :ok <- validate_single_auth_entity(auth_entities, env),
         :ok <- validate_auth_strategies(auth_entities, env),
         :ok <- validate_auth_email_field(auth_entities, env),
         :ok <- validate_auth_no_collisions(auth_entities, env) do
      :ok
    end
  end

  defp validate_single_auth_entity([], _env), do: :ok
  defp validate_single_auth_entity([_], _env), do: :ok

  defp validate_single_auth_entity(entities, env) do
    names = Enum.map(entities, & &1.name)

    compile_error!(
      env,
      "multiple entities declare `authenticatable`: #{inspect(names)}. " <>
        "Caravela supports at most one authenticatable entity per domain."
    )
  end

  defp validate_auth_strategies(entities, env) do
    Enum.each(entities, fn %Entity{name: n, auth: %AuthConfig{strategies: s}} ->
      if s == [] do
        compile_error!(
          env,
          "entity #{inspect(n)} has an authenticatable block but declares no strategies. " <>
            "Add at least `strategy :password` or `strategy :api_token`."
        )
      end

      Enum.each(s, fn
        {:api_token, opts} ->
          scopes = Keyword.get(opts, :scopes, [])

          unless is_list(scopes) and Enum.all?(scopes, &is_atom/1) do
            compile_error!(
              env,
              "api_token :scopes must be a list of atoms, got #{inspect(scopes)}"
            )
          end

          case Keyword.get(opts, :ttl) do
            nil ->
              :ok

            {n, unit} when is_integer(n) and unit in [:hours, :days] ->
              :ok

            other ->
              compile_error!(
                env,
                "api_token :ttl must be {integer, :hours|:days}, got #{inspect(other)}"
              )
          end

        {:password, _} ->
          :ok
      end)
    end)

    :ok
  end

  # The password strategy relies on an `:email` field for lookup. Enforce
  # it at compile time so generated contexts always have a usable
  # identifier.
  defp validate_auth_email_field(entities, env) do
    Enum.each(entities, fn %Entity{name: n, fields: fs, auth: %AuthConfig{} = cfg} ->
      if AuthConfig.password?(cfg) do
        unless Enum.any?(fs, &(&1.name == :email)) do
          compile_error!(
            env,
            "entity #{inspect(n)} uses `strategy :password` but has no :email field. " <>
              "Declare `field :email, :string, required: true` on the entity."
          )
        end
      end
    end)

    :ok
  end

  # The compiler later injects `hashed_password`, `confirmed_at`,
  # `api_tokens` — error early if the user declared any of them by hand.
  defp validate_auth_no_collisions(entities, env) do
    Enum.each(entities, fn %Entity{name: n, fields: fs} ->
      injected = [:hashed_password, :confirmed_at, :api_tokens]

      case Enum.find(fs, &(&1.name in injected)) do
        nil ->
          :ok

        %{name: fname} ->
          compile_error!(
            env,
            "entity #{inspect(n)} declares :#{fname}, but this field is auto-injected " <>
              "by `authenticatable`. Remove the manual declaration."
          )
      end
    end)

    :ok
  end

  defp validate_policies(%Domain{entities: es, policies: ps}, env) do
    entity_names = MapSet.new(es, & &1.name)
    entity_fields = Map.new(es, fn e -> {e.name, MapSet.new(e.fields, & &1.name)} end)

    with :ok <- validate_policy_entities(ps, entity_names, env),
         :ok <- validate_policy_fields(ps, entity_fields, env),
         :ok <- validate_unique_rules(ps, env) do
      :ok
    end
  end

  defp validate_policy_entities(policies, entity_names, env) do
    Enum.each(policies, fn %{entity: e} ->
      unless MapSet.member?(entity_names, e) do
        compile_error!(env, "policy references unknown entity #{inspect(e)}")
      end
    end)

    :ok
  end

  defp validate_policy_fields(policies, entity_fields, env) do
    Enum.each(policies, fn %{entity: entity, fields: rules} ->
      fields = Map.get(entity_fields, entity, MapSet.new())

      Enum.each(rules, fn %{field: f} ->
        unless MapSet.member?(fields, f) do
          compile_error!(
            env,
            "policy for #{inspect(entity)} references unknown field #{inspect(f)}"
          )
        end
      end)
    end)

    :ok
  end

  # With the context-setter `policy` macro, multiple `policy :entity do
  # … end` blocks are additive (useful for conditional / split
  # declarations). The duplication that still matters is within the
  # same (entity, rule_kind[, field|action]) triple: two `scope`s for
  # the same entity, two `field :x` rules, or two `allow :create`s
  # would silently resolve by clause order, which is bewildering.
  defp validate_unique_rules(policies, env) do
    Enum.each(policies, fn %{entity: entity, fields: fields, actions: actions} ->
      # field rules
      field_names = Enum.map(fields, & &1.field)

      case field_names -- Enum.uniq(field_names) do
        [] ->
          :ok

        [dup | _] ->
          compile_error!(
            env,
            "duplicate policy field rule for #{inspect(entity)}.#{dup}"
          )
      end

      # action gates
      gate_actions = Enum.map(actions, & &1.action)

      case gate_actions -- Enum.uniq(gate_actions) do
        [] ->
          :ok

        [dup | _] ->
          compile_error!(
            env,
            "duplicate policy allow rule for #{inspect(entity)}.#{dup}"
          )
      end
    end)

    :ok
  end

  defp compile_error!(env, msg) do
    # Structured errors are preferred for LLM iteration; Elixir's
    # error formatter still annotates the raise with file + line via
    # the macro stacktrace.
    raise Caravela.DSLError,
      message: msg,
      snippet: Caravela.Errors.snippet_from_env(env),
      docs_url: "https://hexdocs.pm/caravela/policies.html"
  end
end
