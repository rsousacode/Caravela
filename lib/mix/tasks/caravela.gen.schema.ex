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
    schemas = EctoSchema.render_all(domain, root: root, force: force?)
    migration = Migration.render(domain)

    files = [migration | schemas]

    MixHelpers.write_files(
      files,
      root,
      force?,
      Keyword.get(opts, :dry_run, false)
    )
  end
end
