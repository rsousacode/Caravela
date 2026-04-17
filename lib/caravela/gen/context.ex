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

  Returns a single `{path, source}` tuple. Regeneration preserves
  anything below the `# --- CUSTOM ---` marker.
  """

  alias Caravela.Schema.Domain
  alias Caravela.{Gen, Naming}

  @template_path Path.expand("../../../priv/templates/context.eex", __DIR__)

  @doc "Render the context file for the domain."
  def render(%Domain{} = domain, opts \\ []) do
    path = Naming.context_file_path(domain.module)
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

        %{
          entity_name: entity.name,
          singular: singular,
          plural: plural,
          module: Naming.entity_module(domain.module, entity.name),
          module_short: Naming.camelize(Naming.singularize(entity.name)),
          list_fn: String.to_atom("list_#{plural}"),
          get_fn: String.to_atom("get_#{singular}"),
          get_bang_fn: String.to_atom("get_#{singular}!"),
          change_fn: String.to_atom("change_#{singular}"),
          create_fn: String.to_atom("create_#{singular}"),
          update_fn: String.to_atom("update_#{singular}"),
          delete_fn: String.to_atom("delete_#{singular}")
        }
      end)

    [
      context_module: Naming.context_module(domain.module),
      domain_module: domain.module,
      repo_module: Naming.repo_module(domain.module),
      entities: entities,
      custom_marker: Gen.Custom.marker_block()
    ]
  end
end
