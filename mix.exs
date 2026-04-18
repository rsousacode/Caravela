defmodule Caravela.MixProject do
  use Mix.Project

  @version "0.5.3"
  @source_url "https://github.com/rsousacode/caravela"

  def project do
    [
      app: :caravela,
      name: "Caravela",
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo.svg",
      extras: [
        "README.md",
        "docs/getting_started.md": [title: "Getting started"],
        "docs/dsl.md": [title: "DSL reference"],
        "docs/generators.md": [title: "Generators"],
        "docs/multi_tenancy.md": [title: "Multi-tenancy"],
        "docs/versioning.md": [title: "API versioning"],
        "docs/graphql.md": [title: "GraphQL with Absinthe"],
        "docs/livesvelte.md": [title: "LiveSvelte frontend"],
        "docs/live_runtime.md": [title: "Live runtime"],
        "docs/flows.md": [title: "Flows"],
        "docs/regeneration.md": [title: "Regeneration"],
        "docs/auth.md": [title: "Authentication"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"],
        NOTICE: [title: "Notice"]
      ],
      groups_for_extras: [
        Guides: ~r"docs/.*\.md",
        Meta: ~r"(CHANGELOG|LICENSE|NOTICE)\.md"
      ],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  defp description do
    "A schema-driven, composable full-stack framework for Phoenix. Declare your domain; sail with the generated code."
  end

  defp package do
    [
      licenses: ["MPL-2.0"],
      files: ~w(lib priv docs mix.exs README.md CHANGELOG.md LICENSE NOTICE),
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.11"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:postgrex, "~> 0.18", optional: true},
      {:live_svelte, "~> 0.14", optional: true},
      {:absinthe, "~> 1.7", optional: true},
      {:absinthe_plug, "~> 1.5", optional: true},
      {:dataloader, "~> 2.0", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
