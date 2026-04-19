defmodule Mix.Tasks.Caravela.Gen.Schema do
  @shortdoc "Generate Ecto schemas and a migration from a Caravela domain"

  @moduledoc """
  Generates Ecto schemas and a migration file from a Caravela domain
  declaration.

      mix caravela.gen.schema MyApp.Domains.Library

  Flags:

    * `--dry-run`  — print the generated files without writing anything
    * `--output DIR` — write under `DIR` instead of the project root
    * `--force`    — overwrite existing files without prompting
  """

  use Mix.Task

  alias Caravela.Gen.{EctoSchema, Migration}
  alias Caravela.MixHelpers

  @switches [dry_run: :boolean, output: :string, force: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)
    domain = MixHelpers.load_domain!(args)

    root = Keyword.get(opts, :output, File.cwd!())
    force? = Keyword.get(opts, :force, false)
    dry_run? = Keyword.get(opts, :dry_run, false)

    schemas = EctoSchema.render_all(domain, root: root, force: force?)
    migration = build_migration!(domain, root, dry_run?)

    files = [migration | schemas]

    MixHelpers.write_files(files, root, force?, dry_run?)
  end

  # Locate any prior migration for this domain's `create_*_tables`
  # step before rendering. Reusing the existing timestamp keeps
  # regeneration idempotent — a second run overwrites the same file
  # instead of appending a new timestamped duplicate that
  # `mix ecto.migrate` would try to run alongside the first.
  #
  # `MixHelpers.write_files/4` already handles the
  # "file exists, are you sure?" prompt on overwrite, so this
  # function's only extra work is warning about *duplicate* prior
  # migrations — a symptom of earlier regenerations that shipped
  # before this fix landed.
  defp build_migration!(domain, root, dry_run?) do
    {timestamp, duplicates} = Migration.reconcile_timestamp(domain, root)

    if duplicates != [], do: warn_duplicates(duplicates, dry_run?)

    Migration.render(domain, timestamp: timestamp)
  end

  defp warn_duplicates(duplicates, dry_run?) do
    unless dry_run? do
      Mix.shell().info("""

      ! #{length(duplicates)} extra migration file(s) with the same `create_*_tables` stem
        already exist — regeneration reused the oldest one. Review and delete
        the rest manually:
      #{Enum.map_join(duplicates, "\n", &"    priv/repo/migrations/#{&1}")}
      """)
    end
  end
end
