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
      |> Gen.Custom.merge_with_file(existing_path, opts)
      |> Caravela.Gen.Format.try_format()
      |> Gen.Custom.stamp_header(generator: :context)

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
          action_access_exprs: action_access_exprs(domain, entity.name, policy)
        }
      end)

    any_on_delete? = Enum.any?(domain.hooks, &(&1.action == :on_delete))
    any_preloads? = Enum.any?(entities, &(&1.preloads != []))

    [
      context_module: Naming.context_module(domain),
      domain_module: domain.module,
      repo_module: Naming.repo_module(domain),
      entities: entities,
      multi_tenant: Domain.multi_tenant?(domain),
      any_on_delete: any_on_delete?,
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
  # `compute_field_access/2`. Every field goes through the dispatch
  # function so the compiler's clause cascade decides the result:
  #
  #   1. Arity-1 rules emit a clause returning a boolean.
  #   2. Arity-2 rules emit an arity-3 clause returning `:per_record`.
  #   3. Un-ruled fields fall through to the per-entity permissive
  #      fallback (for entities with ANY policy block) or the
  #      module-level fallback governed by `default_policy`.
  defp field_access_exprs(%Domain{module: mod}, entity_name, public, _policy) do
    Enum.map(public, fn field ->
      expr =
        "#{inspect(mod)}.__caravela_policy_field_visible__(" <>
          "#{inspect(entity_name)}, #{inspect(field)}, actor)"

      %{name: field, expr: expr}
    end)
  end

  # For each of the three action gates (:create, :update, :delete)
  # generate the right call expression for `action_access/2`:
  #
  #   * If no policy was declared on the entity, the domain's fallback
  #     `__caravela_policy_allow__/3` answers (everything true under
  #     `default_policy: :allow`, everything false under `:deny`).
  #   * If an arity-1 gate exists (`allow :create, fn actor -> ... end`),
  #     call arity-3 — the actor fully determines the answer.
  #   * If an arity-2 gate exists (`allow :update, fn actor, record ->
  #     ... end`), emit the literal atom `:per_record`. Action-level
  #     access can't resolve without a record; the frontend gates per
  #     row / per page using the custom code hook.
  defp action_access_exprs(%Domain{module: mod}, entity_name, policy) do
    Enum.map(Caravela.Policy.action_gate_actions(), fn action ->
      expr = action_access_expr(mod, entity_name, action, policy)
      %{name: action, expr: expr}
    end)
  end

  defp action_access_expr(mod, entity_name, action, nil) do
    # No policy block — the domain's arity-3 fallback is the
    # source of truth (either permissive-everywhere or deny-
    # everywhere under default_policy).
    "#{inspect(mod)}.__caravela_policy_allow__(" <>
      "#{inspect(entity_name)}, #{inspect(action)}, actor)"
  end

  defp action_access_expr(mod, entity_name, action, policy) do
    case Caravela.Policy.Entry.action_gate(policy, action) do
      %Caravela.Policy.ActionGate{arity: 1} ->
        "#{inspect(mod)}.__caravela_policy_allow__(" <>
          "#{inspect(entity_name)}, #{inspect(action)}, actor)"

      %Caravela.Policy.ActionGate{arity: 2} ->
        # Record-dependent gate; the global action_access/2 can't
        # decide without knowing which record. Frontend gates per
        # row via `action_access/3` (added alongside).
        ":per_record"

      nil ->
        # The entity has a policy block but no gate for this action.
        # The compiler's per-entity fallback decides — call arity-3.
        "#{inspect(mod)}.__caravela_policy_allow__(" <>
          "#{inspect(entity_name)}, #{inspect(action)}, actor)"
    end
  end

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
