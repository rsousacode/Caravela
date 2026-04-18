defmodule Mix.Tasks.Caravela.Gen.Auth do
  @shortdoc "Generate the authentication stack for an authenticatable domain"

  @moduledoc """
  Generates the authentication stack from a Caravela domain whose
  authenticatable entity declares an `authenticatable` block.

      mix caravela.gen.auth MyApp.Domains.Identity

  Emits:

    * the auth context module (register, login, logout, sessions, API
      tokens, reset, confirm)
    * the session schema module
    * the Plug pipeline (fetch_current_user, require_auth, require_role,
      require_scope)
    * the LiveView `on_mount` hooks module
    * the auth controller (register / login / logout)
    * a migration creating the session tokens table

  Flags:

    * `--dry-run`  — print the generated files without writing anything
    * `--output DIR` — write under `DIR` instead of the project root
    * `--force`    — overwrite existing files without prompting
  """

  use Mix.Task

  alias Caravela.Gen.Auth
  alias Caravela.MixHelpers

  @switches [
    dry_run: :boolean,
    output: :string,
    force: :boolean,
    skip_ui: :boolean,
    skip_router: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)
    domain = MixHelpers.load_domain!(args)

    root = Keyword.get(opts, :output, File.cwd!())
    skip_ui? = Keyword.get(opts, :skip_ui, false)

    files = Auth.render_all(domain, root: root, skip_ui: skip_ui?)

    MixHelpers.write_files(
      files,
      root,
      Keyword.get(opts, :force, false),
      Keyword.get(opts, :dry_run, false)
    )

    unless Keyword.get(opts, :skip_router, false) do
      Mix.shell().info("\n" <> Auth.router_snippet(domain))
    end
  end
end
