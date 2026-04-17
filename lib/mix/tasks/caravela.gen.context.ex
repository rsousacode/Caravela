defmodule Mix.Tasks.Caravela.Gen.Context do
  @shortdoc "Generate a Phoenix context module from a Caravela domain"

  @moduledoc """
  Generates a Phoenix context module for the given domain, with CRUD
  functions for every entity, authorization via `can_*` permissions,
  and lifecycle hooks via `on_*`.

      mix caravela.gen.context MyApp.Domains.Library

  Flags:

    * `--dry-run`  — print the generated file without writing
    * `--output DIR` — write under `DIR` instead of the project root
    * `--force`    — overwrite existing files without prompting

  Regeneration preserves content below the `# --- CUSTOM ---` marker.
  """

  use Mix.Task

  alias Caravela.Gen.Context
  alias Caravela.MixHelpers

  @switches [dry_run: :boolean, output: :string, force: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)
    domain = MixHelpers.load_domain!(args)
    root = Keyword.get(opts, :output, File.cwd!())

    file = Context.render(domain, root: root)

    MixHelpers.write_files(
      [file],
      root,
      Keyword.get(opts, :force, false),
      Keyword.get(opts, :dry_run, false)
    )
  end
end
