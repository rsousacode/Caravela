defmodule Caravela.MixProject do
  use Mix.Project

  @version "0.2.0"
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
      extras: ["README.md", "CHANGELOG.md", "LICENSE", "NOTICE"],
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
      files: ~w(lib priv mix.exs README.md CHANGELOG.md LICENSE NOTICE),
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
