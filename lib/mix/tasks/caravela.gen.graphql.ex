defmodule Mix.Tasks.Caravela.Gen.Graphql do
  @shortdoc "Generate Absinthe types, queries, and mutations for a Caravela domain"

  @moduledoc """
  Generates an Absinthe schema layer for the given domain: one file each
  for object types, queries, and mutations. All three delegate to the
  generated context module, so authorization, hooks, and multi-tenant
  scoping flow through the Absinthe resolvers for free.

      mix caravela.gen.graphql MyApp.Domains.Library

  Requires the optional `:absinthe` dependency in the consumer app's
  `mix.exs`:

      {:absinthe, "~> 1.7"},
      {:absinthe_plug, "~> 1.5"},
      {:dataloader, "~> 2.0"}

  Flags:

    * `--dry-run`  - print the generated files without writing
    * `--output DIR` - write under `DIR` instead of the project root
    * `--force`    - overwrite existing files without prompting

  Regeneration preserves content below the `# --- CUSTOM ---` marker.
  """

  use Mix.Task

  alias Caravela.Gen.GraphQL
  alias Caravela.MixHelpers

  @switches [dry_run: :boolean, output: :string, force: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)
    ensure_absinthe!()
    domain = MixHelpers.load_domain!(args)
    root = Keyword.get(opts, :output, File.cwd!())
    force? = Keyword.get(opts, :force, false)

    files = GraphQL.render_all(domain, root: root, force: force?)

    MixHelpers.write_files(
      files,
      root,
      force?,
      Keyword.get(opts, :dry_run, false)
    )
  end

  # Absinthe is an optional dep of Caravela - warn the developer at
  # runtime if they try to generate GraphQL code without it.
  defp ensure_absinthe! do
    unless Code.ensure_loaded?(Absinthe.Schema.Notation) do
      Mix.raise("""
      mix caravela.gen.graphql requires Absinthe, but it is not available.

      Add these dependencies to your mix.exs:

          {:absinthe, "~> 1.7"},
          {:absinthe_plug, "~> 1.5"},
          {:dataloader, "~> 2.0"}

      Then run `mix deps.get` and try again.
      """)
    end
  end
end
