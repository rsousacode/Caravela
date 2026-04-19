defmodule Caravela.IR do
  @moduledoc """
  Public, JSON-serializable view of a compiled Caravela domain.

  The internal `Caravela.Schema.Domain` struct is for generator and
  compiler consumption. `Caravela.IR` is the *stable* shape external
  tools, LLMs, and documentation readers consume — a plain map of
  atom keys and primitive values (strings, booleans, integers, maps,
  lists, `nil`) that encodes cleanly through `Jason.encode/1`.

  Anonymous functions inside policies (scope closures, field-rule
  predicates) are *not* included. The IR records only their metadata
  (the fact that a rule exists, its arity, its entity) — the
  implementations live as compiled function clauses on the domain
  module and are not serializable.

  ## Usage

      iex> Caravela.IR.of(MyApp.Domains.Library)
      %{
        domain: "MyApp.Domains.Library",
        caravela_version: "0.8.1",
        multi_tenant: false,
        default_policy: "deny",
        version: nil,
        entities: [...],
        relations: [...],
        hooks: [...]
      }

  Accepts either a domain module (atom) or a compiled
  `%Caravela.Schema.Domain{}` struct.

  ## Stability

  The top-level keys and the shape of entities / fields / relations /
  policies / auth are semver-stable starting in 0.9. New keys may be
  added without a major bump; existing keys keep their shape.
  """

  alias Caravela.Schema.{AuthConfig, Domain, Entity, Field, Hook, Relation}
  alias Caravela.Policy.{ActionGate, Entry, FieldRule}
  alias Caravela.Naming

  @doc """
  Build an IR map for `domain_or_module`. Accepts a domain module atom
  (which must expose `__caravela_domain__/0`) or a compiled
  `Caravela.Schema.Domain` struct.
  """
  @spec of(module() | Domain.t()) :: map()
  def of(domain_module) when is_atom(domain_module) do
    case Code.ensure_loaded(domain_module) do
      {:module, ^domain_module} ->
        if function_exported?(domain_module, :__caravela_domain__, 0) do
          of(domain_module.__caravela_domain__())
        else
          raise ArgumentError,
                "#{inspect(domain_module)} does not use Caravela.Domain " <>
                  "(no __caravela_domain__/0 exported)."
        end

      {:error, reason} ->
        raise ArgumentError,
              "could not load #{inspect(domain_module)}: #{inspect(reason)}"
    end
  end

  def of(%Domain{} = domain) do
    %{
      domain: inspect(domain.module),
      caravela_version: caravela_version(),
      multi_tenant: Domain.multi_tenant?(domain),
      default_policy: Atom.to_string(Domain.default_policy(domain)),
      version: Domain.version(domain),
      entities: Enum.map(domain.entities, &entity_ir(&1, domain)),
      relations: Enum.map(domain.relations, &relation_ir/1),
      hooks: Enum.map(domain.hooks, &hook_ir/1)
    }
  end

  @doc """
  Serialize the IR to a JSON string. Requires `:jason`.
  """
  @spec to_json(map(), keyword()) :: String.t()
  def to_json(ir, opts \\ []) when is_map(ir) do
    case Keyword.get(opts, :pretty, true) do
      true -> Jason.encode!(ir, pretty: true)
      false -> Jason.encode!(ir)
    end
  end

  # --- Entity ------------------------------------------------------------

  defp entity_ir(%Entity{} = entity, %Domain{} = domain) do
    %{
      name: Atom.to_string(entity.name),
      singular: Naming.singular_string(entity.name),
      plural: Naming.plural_string(entity.name),
      module: inspect(Naming.entity_module(domain, entity.name)),
      table: Naming.table_name(domain, entity.name),
      fields: Enum.map(entity.fields, &field_ir/1),
      policy: policy_ir(Domain.policy_for(domain, entity.name)),
      auth: auth_ir(entity.auth)
    }
  end

  # --- Field -------------------------------------------------------------

  defp field_ir(%Field{} = field) do
    opts = field.opts || []
    required = Keyword.get(opts, :required, false)

    # Strip :required from the opts blob since it's promoted to a
    # top-level key. Everything else ships through as-is.
    extra_opts = Keyword.delete(opts, :required)

    %{
      name: Atom.to_string(field.name),
      type: field_type_string(field.type),
      required: required,
      opts: keyword_to_map(extra_opts)
    }
  end

  defp field_type_string(type) when is_atom(type), do: Atom.to_string(type)

  defp field_type_string({:decimal, precision, scale})
       when is_integer(precision) and is_integer(scale),
       do: "decimal(#{precision},#{scale})"

  defp field_type_string(other), do: inspect(other)

  # --- Relation ----------------------------------------------------------

  defp relation_ir(%Relation{} = rel) do
    %{
      kind: Atom.to_string(rel.type),
      from: Atom.to_string(rel.from),
      to: Atom.to_string(rel.to),
      opts: keyword_to_map(rel.opts || [])
    }
  end

  # --- Hook --------------------------------------------------------------

  defp hook_ir(%Hook{} = hook) do
    %{
      action: Atom.to_string(hook.action),
      entity: Atom.to_string(hook.entity),
      arity: hook.arity
    }
  end

  # --- Policy ------------------------------------------------------------

  defp policy_ir(nil), do: nil

  defp policy_ir(%Entry{} = entry) do
    %{
      has_scope: entry.has_scope?,
      field_rules: Enum.map(entry.fields, &field_rule_ir/1),
      action_gates: Enum.map(entry.actions, &action_gate_ir/1)
    }
  end

  defp field_rule_ir(%FieldRule{} = rule) do
    %{
      field: Atom.to_string(rule.field),
      arity: rule.arity
    }
  end

  defp action_gate_ir(%ActionGate{} = gate) do
    %{
      action: Atom.to_string(gate.action),
      arity: gate.arity
    }
  end

  # --- Auth --------------------------------------------------------------

  defp auth_ir(nil), do: nil

  defp auth_ir(%AuthConfig{} = auth) do
    %{
      strategies:
        Enum.map(auth.strategies, fn {kind, opts} ->
          %{kind: Atom.to_string(kind), opts: keyword_to_map(opts)}
        end),
      session: keyword_to_map_or_nil(auth.session),
      confirm: keyword_to_map_or_nil(auth.confirm),
      reset: keyword_to_map_or_nil(auth.reset),
      on_register: auth.on_register?,
      on_login: auth.on_login?
    }
  end

  # --- Helpers -----------------------------------------------------------

  defp keyword_to_map_or_nil(nil), do: nil
  defp keyword_to_map_or_nil(kw), do: keyword_to_map(kw)

  defp keyword_to_map(kw) when is_list(kw) do
    Enum.reduce(kw, %{}, fn
      {k, v}, acc when is_atom(k) -> Map.put(acc, Atom.to_string(k), encode_value(v))
      _, acc -> acc
    end)
  end

  defp keyword_to_map(_), do: %{}

  defp encode_value(v) when is_atom(v) and not is_boolean(v) and not is_nil(v),
    do: Atom.to_string(v)

  defp encode_value({n, unit}) when is_integer(n) and is_atom(unit),
    do: %{"n" => n, "unit" => Atom.to_string(unit)}

  defp encode_value(v) when is_list(v) do
    if Keyword.keyword?(v), do: keyword_to_map(v), else: Enum.map(v, &encode_value/1)
  end

  # Structs (like `Regex`) get stringified — they're opaque to the IR.
  defp encode_value(%_{} = struct), do: inspect(struct)

  defp encode_value(v) when is_map(v),
    do: Map.new(v, fn {k, val} -> {to_string(k), encode_value(val)} end)

  defp encode_value(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v), do: v
  defp encode_value(v), do: inspect(v)

  defp caravela_version do
    case Application.spec(:caravela, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end
end
