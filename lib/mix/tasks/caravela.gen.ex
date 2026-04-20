defmodule Mix.Tasks.Caravela.Gen do
  @shortdoc "Generate everything for a Caravela domain (schemas, migration, context, API)"

  @moduledoc """
  All-in-one generator. Produces:

    * Ecto schemas and a migration (as `mix caravela.gen.schema`)
    * A Phoenix context module (as `mix caravela.gen.context`)
    * JSON controllers and a router scope snippet (as `mix caravela.gen.api`)

      mix caravela.gen MyApp.Domains.Library

  Flags:

    * `--dry-run`  - print the generated files without writing
    * `--output DIR` - write under `DIR` instead of the project root
    * `--force`    - overwrite existing files without prompting
    * `--no-scope` - skip printing the router snippet

  Regeneration preserves content below the `# --- CUSTOM ---` marker
  in every file that has one (schemas, contexts, controllers).
  """

  use Mix.Task

  alias Caravela.Gen.{Context, Controller, EctoSchema, Migration, RouterScope}
  alias Caravela.MixHelpers

  @switches [dry_run: :boolean, output: :string, force: :boolean, scope: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)
    domain = MixHelpers.load_domain!(args)
    root = Keyword.get(opts, :output, File.cwd!())
    force? = Keyword.get(opts, :force, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    gen_opts = [root: root, force: force?]

    schemas = EctoSchema.render_all(domain, gen_opts)
    migration = reconciled_migration(domain, root, dry_run?)
    context = Context.render(domain, gen_opts)
    controllers = Controller.render_all(domain, gen_opts)

    files = [migration | schemas] ++ [context] ++ controllers

    MixHelpers.write_files(files, root, force?, dry_run?)

    if Keyword.get(opts, :scope, true) and not dry_run? do
      Mix.shell().info("\n" <> RouterScope.render(domain))
    end

    :ok
  end

  # Reuse an existing migration's timestamp so regenerating doesn't
  # append a duplicate `create_*_tables.exs` under
  # `priv/repo/migrations/`. Mirrors the behaviour in
  # `Mix.Tasks.Caravela.Gen.Schema`.
  defp reconciled_migration(domain, root, dry_run?) do
    {timestamp, duplicates} = Migration.reconcile_timestamp(domain, root)

    if duplicates != [] and not dry_run? do
      Mix.shell().info("""

      ! #{length(duplicates)} extra migration file(s) with the same `create_*_tables` stem
        already exist - regeneration reused the oldest one. Review and delete
        the rest manually:
      #{Enum.map_join(duplicates, "\n", &"    priv/repo/migrations/#{&1}")}
      """)
    end

    Migration.render(domain, timestamp: timestamp)
  end
end
