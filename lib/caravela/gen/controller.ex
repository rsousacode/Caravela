defmodule Caravela.Gen.Controller do
  @moduledoc """
  Generates one Phoenix JSON controller per entity in a
  `Caravela.Schema.Domain`.

  Each controller provides standard REST actions (`index`, `show`,
  `create`, `update`, `delete`) and delegates to the generated context
  module. Authorization and hooks are enforced inside the context —
  the controller only translates `{:ok, _} | {:error, _}` tuples into
  HTTP status codes.

  Returns a list of `{path, source}` tuples. Files preserve content
  below the `# --- CUSTOM ---` marker on regeneration.
  """

  alias Caravela.Schema.Domain
  alias Caravela.{Gen, Naming}

  @template_path Path.expand("../../../priv/templates/controller.eex", __DIR__)

  @doc "Render every controller for the domain."
  def render_all(%Domain{} = domain, opts \\ []) do
    Enum.map(domain.entities, &render_entity(domain, &1, opts))
  end

  @doc "Render a single controller for one entity."
  def render_entity(%Domain{} = domain, entity, opts \\ []) do
    path = Naming.controller_file_path(domain.module, entity.name)
    root = Keyword.get(opts, :root, File.cwd!())
    existing_path = Path.join(root, path)

    assigns = build_assigns(domain, entity)
    rendered = EEx.eval_file(@template_path, assigns: assigns, trim: true)

    source =
      rendered
      |> Gen.Custom.merge_with_file(existing_path)
      |> Caravela.Gen.Format.try_format()

    {path, source}
  end

  # --- Assigns -----------------------------------------------------------

  defp build_assigns(%Domain{} = domain, entity) do
    singular = Naming.singular_string(entity.name)
    plural = Naming.plural_string(entity.name)
    context_module = Naming.context_module(domain.module)
    [context_short | _] = context_module |> Module.split() |> Enum.reverse()

    [
      controller_module: Naming.controller_module(domain.module, entity.name),
      context_module: context_module,
      context_short: context_short,
      domain_module: domain.module,
      entity_name: entity.name,
      singular: singular,
      plural: plural,
      list_fn: String.to_atom("list_#{plural}"),
      get_fn: String.to_atom("get_#{singular}"),
      create_fn: String.to_atom("create_#{singular}"),
      update_fn: String.to_atom("update_#{singular}"),
      delete_fn: String.to_atom("delete_#{singular}"),
      custom_marker: Gen.Custom.marker_block()
    ]
  end
end
