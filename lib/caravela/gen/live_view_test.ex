defmodule Caravela.Gen.LiveViewTest do
  @moduledoc """
  Generates ExUnit tests for every `:live` entity's three LiveView
  modules (Index / Show / Form). One test file per entity,
  organized as `describe` blocks per module with one test per
  action — a CI-ready skeleton the developer fills in with
  fixtures and assertions specific to their domain.

  The generated tests use the standard Phoenix test stack
  (`Phoenix.ConnTest`, `Phoenix.LiveViewTest`) and assume the
  consumer app has a `*.ConnCase` module under
  `test/support/conn_case.ex` — which `mix phx.new` emits by
  default, so no extra setup is needed.

  Each generated test carries a `# TODO:` line pointing at the
  fixture hole to fill — the generator cannot know the app's
  context factories, so it stops short of full assertions.

  Returns a list of `{path, source}` tuples. Custom code below the
  `# --- CUSTOM ---` marker is preserved on regeneration.
  """

  alias Caravela.Schema.{Domain, Entity}
  alias Caravela.{Gen, Naming}

  @template_path Path.expand("../../../priv/templates/live_view_test.eex", __DIR__)

  @doc "Generate a test file per `:live` entity in the domain."
  @spec render_all(Domain.t(), keyword()) :: [{String.t(), String.t()}]
  def render_all(%Domain{} = domain, opts \\ []) do
    domain.entities
    |> Enum.filter(&(&1.frontend == :live))
    |> Enum.map(&render_entity(domain, &1, opts))
  end

  @doc "Generate a single entity's LiveView test file."
  @spec render_entity(Domain.t(), Entity.t(), keyword()) :: {String.t(), String.t()}
  def render_entity(%Domain{} = domain, %Entity{} = entity, opts \\ []) do
    path = test_file_path(domain, entity)
    root = Keyword.get(opts, :root, File.cwd!())
    existing = Path.join(root, path)

    assigns = build_assigns(domain, entity)
    rendered = EEx.eval_file(@template_path, assigns: assigns, trim: true)

    source =
      rendered
      |> Gen.Custom.merge_with_file(existing, opts)
      |> Caravela.Gen.Format.try_format()
      |> Gen.Custom.stamp_header(generator: :live_view_test)

    {path, source}
  end

  @doc "Path to the generated test file, relative to the project root."
  @spec test_file_path(Domain.t(), Entity.t()) :: String.t()
  def test_file_path(%Domain{} = domain, %Entity{} = entity) do
    web_root = Naming.web_module(domain) |> Module.split() |> List.first() |> Macro.underscore()
    ctx_short = Naming.context_short(domain)
    singular = Naming.singular_string(entity.name)

    base_segments =
      case Domain.version(domain) do
        nil -> ["test", web_root, "live", ctx_short]
        v -> ["test", web_root, "live", v, ctx_short]
      end

    Path.join(base_segments ++ ["#{singular}_live_test.exs"])
  end

  defp build_assigns(%Domain{} = domain, %Entity{} = entity) do
    singular = Naming.singular_string(entity.name)
    plural = Naming.plural_string(entity.name)
    context_module = Naming.context_module(domain)

    [
      module: test_module(domain, entity),
      conn_case: conn_case_module(domain),
      web_module_alias: Naming.web_module(domain) |> inspect(),
      domain_module: domain.module,
      context_module: context_module,
      context_short: context_module |> Module.split() |> List.last(),
      entity_name: entity.name,
      singular: singular,
      plural: plural,
      index_path: route_prefix(domain, entity),
      list_fn: "list_#{plural}",
      create_fn: "create_#{singular}",
      index_module: Naming.live_module(domain, entity.name, :index),
      show_module: Naming.live_module(domain, entity.name, :show),
      form_module: Naming.live_module(domain, entity.name, :form),
      custom_marker: Gen.Custom.marker_block()
    ]
  end

  defp test_module(%Domain{} = domain, %Entity{} = entity) do
    # Name: `<Web>.[V1.]<Context>.<Entity>LiveTest` — sibling of the
    # LiveView modules themselves, one suffix deeper in camelization.
    index_mod = Naming.live_module(domain, entity.name, :index)

    parent =
      index_mod
      |> Module.split()
      |> Enum.drop(-1)
      |> Module.concat()

    entity_short = Naming.camelize(Naming.singularize(entity.name))
    Module.concat(parent, "#{entity_short}LiveTest")
  end

  defp conn_case_module(%Domain{} = domain) do
    # Standard Phoenix convention: `<App>Web.ConnCase` under
    # `test/support/conn_case.ex`. Not derived from the domain;
    # we infer the web module from the Caravela context naming
    # rule.
    Module.concat(Naming.web_module(domain), "ConnCase")
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
