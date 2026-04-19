defmodule Caravela.Gen.RestControllerTest do
  @moduledoc """
  Generates ExUnit tests for every `:rest` entity's Phoenix
  controller. One test file per entity, one `describe` per action,
  one test per happy/unhappy path. Uses the standard
  `Phoenix.ConnTest` stack and assumes `*.ConnCase` under
  `test/support/conn_case.ex`.

  Tests are CI-ready: `mix test` picks them up, no extra
  configuration required beyond the consumer app's existing Phoenix
  test setup. Fixture hooks are marked `# TODO:` because the
  generator can't infer the app's factories.

  Returns a list of `{path, source}` tuples. Custom code below the
  `# --- CUSTOM ---` marker is preserved on regeneration.
  """

  alias Caravela.Schema.{Domain, Entity}
  alias Caravela.{Gen, Naming}

  @template_path Path.expand("../../../priv/templates/rest_controller_test.eex", __DIR__)

  @doc "Generate a test file per `:rest` entity in the domain."
  @spec render_all(Domain.t(), keyword()) :: [{String.t(), String.t()}]
  def render_all(%Domain{} = domain, opts \\ []) do
    domain.entities
    |> Enum.filter(&(&1.frontend == :rest))
    |> Enum.map(&render_entity(domain, &1, opts))
  end

  @doc "Generate a single entity's controller test file."
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
      |> Gen.Custom.stamp_header(generator: :rest_controller_test)

    {path, source}
  end

  @doc "Path to the generated controller test file."
  @spec test_file_path(Domain.t(), Entity.t()) :: String.t()
  def test_file_path(%Domain{} = domain, %Entity{} = entity) do
    web_root = Naming.web_module(domain) |> Module.split() |> List.first() |> Macro.underscore()
    filename = "#{Naming.singular_string(entity.name)}_controller_test.exs"

    case Domain.version(domain) do
      nil -> Path.join(["test", web_root, "controllers", filename])
      v -> Path.join(["test", web_root, "controllers", v, filename])
    end
  end

  defp build_assigns(%Domain{} = domain, %Entity{} = entity) do
    singular = Naming.singular_string(entity.name)
    plural = Naming.plural_string(entity.name)
    context_module = Naming.context_module(domain)
    controller_module = Naming.controller_module(domain, entity.name)

    [
      module: Module.concat(controller_module, "Test"),
      conn_case: Module.concat(Naming.web_module(domain), "ConnCase"),
      domain_module: domain.module,
      context_module: context_module,
      context_short: context_module |> Module.split() |> List.last(),
      controller_module: controller_module,
      entity_name: entity.name,
      singular: singular,
      plural: plural,
      index_path: route_prefix(domain, entity),
      create_fn: "create_#{singular}",
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
