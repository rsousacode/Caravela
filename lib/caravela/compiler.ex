defmodule Caravela.Compiler do
  @moduledoc """
  Compile-time hook that assembles and validates a domain IR.

  Wired up via `@before_compile Caravela.Compiler` from modules that
  `use Caravela.Domain`.
  """

  alias Caravela.Schema.{Domain, Entity, Field, Relation, Hook, Permission}
  alias Caravela.{Tenant, Types}

  @relation_types ~w(has_many has_one belongs_to many_to_many)a
  @version_re ~r/^v\d+$/

  defmacro __before_compile__(env) do
    entities = env.module |> Module.get_attribute(:caravela_entities) |> Enum.reverse()
    relations = env.module |> Module.get_attribute(:caravela_relations) |> Enum.reverse()
    hooks = env.module |> Module.get_attribute(:caravela_hooks) |> Enum.reverse()
    permissions = env.module |> Module.get_attribute(:caravela_permissions) |> Enum.reverse()
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
      permissions: permissions,
      opts: opts
    }

    :ok = validate!(domain, env)
    domain = Tenant.inject(domain)

    Module.put_attribute(env.module, :caravela_domain_compiled, domain)

    quote do
      @doc false
      def __caravela_domain__ do
        @caravela_domain_compiled
      end

      # Fallbacks. Must come after the specific clauses emitted by each
      # on_* / can_* macro.
      @doc false
      def __caravela_hook__(:on_create, _entity, changeset, _context), do: changeset
      def __caravela_hook__(:on_update, _entity, changeset, _context), do: changeset
      def __caravela_hook__(:on_delete, _entity, _entity_value, _context), do: :ok

      @doc false
      def __caravela_permission__(:can_read, _entity, query, _context), do: query
      def __caravela_permission__(:can_create, _entity, _context), do: true
      def __caravela_permission__(:can_update, _entity, _entity_value, _context), do: true
      def __caravela_permission__(:can_delete, _entity, _entity_value, _context), do: true
    end
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
         :ok <- validate_permission_entities(domain, env),
         :ok <- validate_unique_permissions(domain, env) do
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

  defp validate_permission_entities(%Domain{entities: es, permissions: ps}, env) do
    names = MapSet.new(es, & &1.name)

    Enum.each(ps, fn %Permission{action: a, entity: e} ->
      unless MapSet.member?(names, e) do
        compile_error!(env, "permission #{a} references unknown entity #{inspect(e)}")
      end
    end)

    :ok
  end

  defp validate_unique_permissions(%Domain{permissions: ps}, env) do
    pairs = Enum.map(ps, &{&1.action, &1.entity})

    case pairs -- Enum.uniq(pairs) do
      [] ->
        :ok

      [{a, e} | _] ->
        compile_error!(env, "duplicate permission #{a} for entity #{inspect(e)}")
    end
  end

  defp compile_error!(env, msg) do
    raise CompileError,
      file: Map.get(env, :file, "unknown"),
      line: Map.get(env, :line, 0),
      description: "Caravela: " <> msg
  end
end
