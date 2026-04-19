defmodule Caravela.Gen.SvelteTest do
  @moduledoc """
  Generates Vitest + `@testing-library/svelte` smoke tests — one
  `*.test.ts` file colocated next to every generated Svelte
  component. The tests assert the component mounts with minimally
  valid props and exposes key entity fields in the DOM. They are
  deliberately thin — a CI oracle that catches "my prop contract
  changed and the component now throws", not a full UX regression
  suite.

  Consumer apps need `vitest` and `@testing-library/svelte` as
  dev-dependencies. Caravela's generated `package.json` entries
  (shipped as documentation in v0.12+) pin compatible versions.

  Returns a list of `{path, source}` tuples.
  """

  alias Caravela.Schema.{Domain, Entity}
  alias Caravela.{Gen, Naming}

  @index_template Path.expand("../../../priv/templates/svelte_index_test.eex", __DIR__)
  @show_template Path.expand("../../../priv/templates/svelte_show_test.eex", __DIR__)
  @form_template Path.expand("../../../priv/templates/svelte_form_test.eex", __DIR__)

  @doc "Generate a Vitest file per Svelte component kind per entity."
  @spec render_all(Domain.t(), keyword()) :: [{String.t(), String.t()}]
  def render_all(%Domain{} = domain, opts \\ []) do
    Enum.flat_map(domain.entities, fn entity ->
      [
        render_component(domain, entity, :index, opts),
        render_component(domain, entity, :show, opts),
        render_component(domain, entity, :form, opts)
      ]
    end)
  end

  @doc "Generate a single test file."
  @spec render_component(Domain.t(), Entity.t(), :index | :show | :form, keyword()) ::
          {String.t(), String.t()}
  def render_component(%Domain{} = domain, %Entity{} = entity, kind, opts \\ []) do
    path = test_file_path(domain, entity, kind)
    root = Keyword.get(opts, :root, File.cwd!())
    existing = Path.join(root, path)

    assigns = build_assigns(domain, entity, kind)
    template = Map.fetch!(templates(), kind)
    rendered = EEx.eval_file(template, assigns: assigns, trim: true)

    source =
      rendered
      |> Gen.Custom.merge_with_file(existing, style: :ts, force: Keyword.get(opts, :force, false))
      |> Gen.Custom.stamp_header(style: :ts, generator: :"svelte_#{kind}_test")

    {path, source}
  end

  defp templates do
    %{index: @index_template, show: @show_template, form: @form_template}
  end

  @doc "Colocated test-file path next to the generated Svelte file."
  @spec test_file_path(Domain.t(), Entity.t(), :index | :show | :form) :: String.t()
  def test_file_path(%Domain{} = domain, %Entity{} = entity, kind) do
    component = Naming.svelte_component_name(entity.name, kind)
    ctx_short = Naming.context_short(domain)

    segments =
      case Domain.version(domain) do
        nil -> ["assets", "svelte", ctx_short]
        v -> ["assets", "svelte", v, ctx_short]
      end

    Path.join(segments ++ ["#{component}.test.ts"])
  end

  defp build_assigns(%Domain{} = domain, %Entity{} = entity, kind) do
    [
      component_name: Naming.svelte_component_name(entity.name, kind),
      entity_ts: Naming.camelize(Naming.singularize(entity.name)),
      singular: Naming.singular_string(entity.name),
      plural: Naming.plural_string(entity.name),
      default_field_access: field_access_literal(entity),
      frontend: Atom.to_string(entity.frontend),
      domain_module: inspect(domain.module)
    ]
  end

  # JSON-ish literal of `{ field: true, ... }` covering every
  # public field — enough for the component to mount without prop
  # errors. Matches the default field-access literal the Svelte
  # generator ships.
  defp field_access_literal(%Entity{fields: fields}) do
    fields
    |> Enum.map(fn f -> "#{f.name}: true" end)
    |> Enum.join(", ")
    |> then(&("{ " <> &1 <> " }"))
  end
end
