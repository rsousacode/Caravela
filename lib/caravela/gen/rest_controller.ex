defmodule Caravela.Gen.RestController do
  @moduledoc """
  Generates Phoenix controllers that render Svelte components via
  `caravela_svelte`'s Inertia-style transport (`:rest` render mode).

  One controller per entity. Actions: `index`, `show`, `new`, `edit`,
  `create`, `update`, `delete`. Each action calls
  `CaravelaSvelte.Caravela.put_field_access/2` before rendering so
  the Svelte component receives the entity's `field_access` prop
  under the same key regardless of render mode.

  Unlike `Caravela.Gen.Controller` (which emits pure JSON APIs),
  controllers produced here assume the consumer app has
  `caravela_svelte` installed and mounted in its router.

  The generator only emits files for entities declared with
  `frontend: :rest` in the `Caravela.Domain` DSL. When an entity also
  declares `realtime: true`, the generated controller calls
  `CaravelaSvelte.Caravela.broadcast_patch/3` after each
  state-changing action - create, update, delete.

  Returns a list of `{path, source}` tuples. Files preserve content
  below the `# --- CUSTOM ---` marker on regeneration.
  """

  alias Caravela.Schema.{Domain, Entity}
  alias Caravela.{Gen, Naming}

  @template_path Path.expand("../../../priv/templates/rest_controller.eex", __DIR__)

  @doc "Render a controller for every `:rest` entity in the domain."
  @spec render_all(Domain.t(), keyword()) :: [{String.t(), String.t()}]
  def render_all(%Domain{} = domain, opts \\ []) do
    domain.entities
    |> Enum.filter(&(&1.frontend == :rest))
    |> Enum.map(&render_entity(domain, &1, opts))
  end

  @doc "Render a single `:rest` controller."
  @spec render_entity(Domain.t(), Entity.t(), keyword()) :: {String.t(), String.t()}
  def render_entity(%Domain{} = domain, %Entity{} = entity, opts \\ []) do
    path = Naming.controller_file_path(domain, entity.name)
    root = Keyword.get(opts, :root, File.cwd!())
    existing = Path.join(root, path)

    assigns = build_assigns(domain, entity)
    rendered = EEx.eval_file(@template_path, assigns: assigns, trim: true)

    source =
      rendered
      |> Gen.Custom.merge_with_file(existing, opts)
      |> Caravela.Gen.Format.try_format()
      |> Gen.Custom.stamp_header(generator: :rest_controller)

    {path, source}
  end

  defp build_assigns(%Domain{} = domain, %Entity{} = entity) do
    singular = Naming.singular_string(entity.name)
    plural = Naming.plural_string(entity.name)
    context_module = Naming.context_module(domain)
    [context_short | _] = context_module |> Module.split() |> Enum.reverse()
    entity_module = Naming.entity_module(domain, entity.name)
    [entity_short | _] = entity_module |> Module.split() |> Enum.reverse()

    [
      controller_module: Naming.controller_module(domain, entity.name),
      context_module: context_module,
      context_short: context_short,
      domain_module: domain.module,
      entity_name: entity.name,
      entity_module: entity_module,
      entity_short: entity_short,
      singular: singular,
      plural: plural,
      index_path: route_prefix(domain, entity),
      list_fn: "list_#{plural}",
      get_fn: "get_#{singular}",
      create_fn: "create_#{singular}",
      update_fn: "update_#{singular}",
      delete_fn: "delete_#{singular}",
      change_fn: "change_#{singular}",
      realtime: entity.realtime?,
      component_index: Naming.svelte_component_ref(domain, entity.name, :index),
      component_show: Naming.svelte_component_ref(domain, entity.name, :show),
      component_form: Naming.svelte_component_ref(domain, entity.name, :form),
      multi_tenant: Domain.multi_tenant?(domain),
      custom_marker: Gen.Custom.marker_block()
    ]
  end

  defp route_prefix(%Domain{} = domain, %Entity{} = entity) do
    ctx_short = Naming.context_short(domain)
    plural = Naming.plural_string(entity.name)

    case Domain.version(domain) do
      nil -> "/#{ctx_short}/#{plural}"
      v -> "/#{v}/#{ctx_short}/#{plural}"
    end
  end
end
