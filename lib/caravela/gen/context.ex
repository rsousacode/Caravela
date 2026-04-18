defmodule Caravela.Gen.Context do
  @moduledoc """
  Generates a Phoenix context module for a `Caravela.Schema.Domain`.

  The module lives at `lib/<app>/<context>.ex` (e.g.
  `lib/my_app/library.ex`) and exposes the standard Phoenix CRUD
  functions per entity:

    * `list_<plural>/1`
    * `get_<singular>/2`, `get_<singular>!/2`
    * `change_<singular>/2`
    * `create_<singular>/2`
    * `update_<singular>/3`
    * `delete_<singular>/2`

  Every write path runs the corresponding `on_create`/`on_update`/
  `on_delete` hook and `can_*` permission declared on the domain.
  Reads scope through `can_read` automatically.

  Read paths (`list_*`, `get_*`, `get_*!`) preload every `belongs_to`
  association declared on the entity so the generated Svelte
  components can follow `book.author.name` without tripping over
  `%Ecto.Association.NotLoaded{}` structs on the wire.

  Returns a single `{path, source}` tuple. Regeneration preserves
  anything below the `# --- CUSTOM ---` marker.
  """

  alias Caravela.Schema.{Domain, Relation}
  alias Caravela.Policy.Entry, as: PolicyEntry
  alias Caravela.{Gen, Naming}

  @template_path Path.expand("../../../priv/templates/context.eex", __DIR__)

  @doc "Render the context file for the domain."
  def render(%Domain{} = domain, opts \\ []) do
    path = Naming.context_file_path(domain)
    root = Keyword.get(opts, :root, File.cwd!())
    existing_path = Path.join(root, path)

    assigns = build_assigns(domain)
    rendered = EEx.eval_file(@template_path, assigns: assigns, trim: true)

    source =
      rendered
      |> Gen.Custom.merge_with_file(existing_path)
      |> Caravela.Gen.Format.try_format()

    {path, source}
  end

  # --- Assigns -----------------------------------------------------------

  defp build_assigns(%Domain{} = domain) do
    entities =
      Enum.map(domain.entities, fn entity ->
        singular = Naming.singular_string(entity.name)
        plural = Naming.plural_string(entity.name)
        policy = Domain.policy_for(domain, entity.name)
        public = public_field_names(entity)

        %{
          entity_name: entity.name,
          singular: singular,
          plural: plural,
          module: Naming.entity_module(domain, entity.name),
          module_short: Naming.camelize(Naming.singularize(entity.name)),
          list_fn: String.to_atom("list_#{plural}"),
          get_fn: String.to_atom("get_#{singular}"),
          get_bang_fn: String.to_atom("get_#{singular}!"),
          change_fn: String.to_atom("change_#{singular}"),
          create_fn: String.to_atom("create_#{singular}"),
          update_fn: String.to_atom("update_#{singular}"),
          delete_fn: String.to_atom("delete_#{singular}"),
          preloads: belongs_to_preloads(domain, entity.name),
          public_fields: public,
          field_access_exprs: field_access_exprs(domain, entity.name, public, policy),
          has_policy_scope: not is_nil(policy) and policy.has_scope?,
          has_policy_fields: not is_nil(policy) and policy.fields != [],
          has_policy_actions: not is_nil(policy) and policy.actions != []
        }
      end)

    any_can_create? = Enum.any?(domain.permissions, &(&1.action == :can_create))
    any_can_update? = Enum.any?(domain.permissions, &(&1.action == :can_update))
    any_can_delete? = Enum.any?(domain.permissions, &(&1.action == :can_delete))
    any_on_delete? = Enum.any?(domain.hooks, &(&1.action == :on_delete))

    any_policies? =
      Enum.any?(entities, &(&1.has_policy_scope or &1.has_policy_fields or &1.has_policy_actions))

    any_policy_fields? = Enum.any?(entities, & &1.has_policy_fields)
    any_policy_actions? = Enum.any?(entities, & &1.has_policy_actions)

    any_preloads? = Enum.any?(entities, &(&1.preloads != []))

    [
      context_module: Naming.context_module(domain),
      domain_module: domain.module,
      repo_module: Naming.repo_module(domain),
      entities: entities,
      multi_tenant: Domain.multi_tenant?(domain),
      any_can_create: any_can_create?,
      any_can_update: any_can_update?,
      any_can_delete: any_can_delete?,
      any_on_delete: any_on_delete?,
      any_policies: any_policies?,
      any_policy_fields: any_policy_fields?,
      any_policy_actions: any_policy_actions?,
      any_preloads: any_preloads?,
      custom_marker: Gen.Custom.marker_block()
    ]
  end

  # Public fields are the fields that survive tenant + auth filtering
  # on the way to the client. We reuse the Svelte generator's helper to
  # stay consistent.
  defp public_field_names(entity),
    do: Enum.map(Caravela.Gen.Svelte.public_fields_for(entity), & &1.name)

  # For each public field, build the source expression rendered into
  # `compute_field_access/2`. Arity-1 rules resolve to a boolean call;
  # arity-2 rules resolve to `:per_record` so the caller evaluates per
  # row. Fields without a rule default to `true`.
  defp field_access_exprs(%Domain{module: mod}, entity_name, public, policy) do
    rules = rules_map(policy)

    Enum.map(public, fn field ->
      expr =
        case Map.get(rules, field) do
          nil ->
            "true"

          1 ->
            "#{inspect(mod)}.__caravela_policy_field_visible__(" <>
              "#{inspect(entity_name)}, #{inspect(field)}, actor)"

          2 ->
            ":per_record"
        end

      %{name: field, expr: expr}
    end)
  end

  defp rules_map(nil), do: %{}
  defp rules_map(%PolicyEntry{fields: rules}), do: Map.new(rules, fn r -> {r.field, r.arity} end)

  # Returns the list of association atoms a `belongs_to` relation from
  # `entity_name` points to. Read paths preload these so the Svelte
  # components never see a `%Ecto.Association.NotLoaded{}` on the wire.
  defp belongs_to_preloads(%Domain{relations: rels}, entity_name) do
    rels
    |> Enum.flat_map(fn
      %Relation{from: ^entity_name, to: to, type: :belongs_to} ->
        [Naming.belongs_to_name(to)]

      %Relation{from: from, to: ^entity_name, type: type}
      when type in [:has_many, :has_one] ->
        [Naming.belongs_to_name(from)]

      _ ->
        []
    end)
    |> Enum.uniq()
  end
end
