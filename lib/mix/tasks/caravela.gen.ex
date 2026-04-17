defmodule Mix.Tasks.Caravela.Gen do
  @shortdoc "Generate everything for a Caravela domain (schemas, migration, context, API)"

  @moduledoc """
  All-in-one generator. Produces:

    * Ecto schemas and a migration (as `mix caravela.gen.schema`)
    * A Phoenix context module (as `mix caravela.gen.context`)
    * JSON controllers and a router scope snippet (as `mix caravela.gen.api`)

      mix caravela.gen MyApp.Domains.Library

  Flags:

    * `--dry-run`  — print the generated files without writing
    * `--output DIR` — write under `DIR` instead of the project root
    * `--force`    — overwrite existing files without prompting
    * `--no-scope` — skip printing the router snippet

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

    schemas = EctoSchema.render_all(domain, root: root)
    migration = Migration.render(domain)
    context = Context.render(domain, root: root)
    controllers = Controller.render_all(domain, root: root)

    files = [migration | schemas] ++ [context] ++ controllers

    MixHelpers.write_files(
      files,
      root,
      Keyword.get(opts, :force, false),
      Keyword.get(opts, :dry_run, false)
    )

    if Keyword.get(opts, :scope, true) and not Keyword.get(opts, :dry_run, false) do
      Mix.shell().info("\n" <> RouterScope.render(domain))
    end

    :ok
  end
end
