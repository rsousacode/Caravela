defmodule Caravela.MixProject do
  use Mix.Project

  def project do
    [
      app: :caravela,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
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
      files: ~w(lib priv mix.exs README.md LICENSE NOTICE),
      links: %{}
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
