defmodule Mix.Tasks.Caravela.Gen.Api do
  @shortdoc "Generate JSON controllers for a Caravela domain"

  @moduledoc """
  Generates one Phoenix JSON controller per entity in the domain and
  prints a router scope snippet the developer can paste into
  `lib/<app>_web/router.ex`.

      mix caravela.gen.api MyApp.Domains.Library

  Flags:

    * `--dry-run`  - print the generated files without writing
    * `--output DIR` - write under `DIR` instead of the project root
    * `--force`    - overwrite existing files without prompting
    * `--no-scope` - skip printing the router snippet

  Regeneration preserves content below the `# --- CUSTOM ---` marker.
  """

  use Mix.Task

  alias Caravela.Gen.{Controller, RouterScope}
  alias Caravela.MixHelpers

  @switches [dry_run: :boolean, output: :string, force: :boolean, scope: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)
    domain = MixHelpers.load_domain!(args)
    root = Keyword.get(opts, :output, File.cwd!())
    force? = Keyword.get(opts, :force, false)

    files = Controller.render_all(domain, root: root, force: force?)

    MixHelpers.write_files(
      files,
      root,
      force?,
      Keyword.get(opts, :dry_run, false)
    )

    if Keyword.get(opts, :scope, true) and not Keyword.get(opts, :dry_run, false) do
      Mix.shell().info("\n" <> RouterScope.render(domain))
    end

    :ok
  end
end
