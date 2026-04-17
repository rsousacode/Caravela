defmodule Mix.Tasks.Caravela.Gen.Live do
  @shortdoc "Generate LiveView modules + typed Svelte components for a Caravela domain"

  @moduledoc """
  Generates the frontend layer for a Caravela domain: a trio of LiveView
  modules (index/show/form) per entity, plus typed Svelte components and
  a TypeScript interfaces file.

      mix caravela.gen.live MyApp.Domains.Library

  Generated files (single-version, non-tenant example):

      lib/my_app_web/live/library/book_live/{index,show,form}.ex
      assets/svelte/library/{BookIndex,BookShow,BookForm}.svelte
      assets/svelte/types/library.ts

  Every LiveView mounts its Svelte component via `<LiveSvelte.render>`,
  and delegates to the generated context module for CRUD calls —
  authorization, hooks, and multi-tenant scoping flow through for free.

  Requires LiveSvelte in the consumer app:

      {:live_svelte, "~> 0.19"}

  After `mix deps.get`, follow the LiveSvelte docs to wire it into
  `assets/js/app.js`.

  Flags:

    * `--dry-run`  — print the generated files without writing
    * `--output DIR` — write under `DIR` instead of the project root
    * `--force`    — overwrite existing files without prompting
    * `--with-domain` — also emit a `Caravela.Live.Domain` companion
      module per entity and generate `form.ex` from the Template-backed
      variant. Useful as an onramp to the `Caravela.Live.*` runtime.

  Regeneration preserves content below the `# --- CUSTOM ---` /
  `<!-- --- CUSTOM --- -->` marker in every file.
  """

  use Mix.Task

  alias Caravela.Gen.{LiveRoute, LiveView, Svelte}
  alias Caravela.MixHelpers

  @switches [
    dry_run: :boolean,
    output: :string,
    force: :boolean,
    with_domain: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)
    domain = MixHelpers.load_domain!(args)
    root = Keyword.get(opts, :output, File.cwd!())
    with_domain? = Keyword.get(opts, :with_domain, false)

    warn_if_live_svelte_missing()

    live_files = LiveView.render_all(domain, root: root, with_domain: with_domain?)
    svelte_files = Svelte.render_all(domain, root: root)

    MixHelpers.write_files(
      live_files ++ svelte_files,
      root,
      Keyword.get(opts, :force, false),
      Keyword.get(opts, :dry_run, false)
    )

    unless Keyword.get(opts, :dry_run, false) do
      Mix.shell().info("\n" <> LiveRoute.render(domain))

      Mix.shell().info("""

      Next steps:

        1. Add {:live_svelte, "~> 0.19"} to mix.exs (if you haven't already).
        2. Install deps:  mix deps.get && cd assets && npm install && cd ..
        3. Wire LiveSvelte into assets/js/app.js (see LiveSvelte docs).
        4. Paste the router snippet above into lib/<app>_web/router.ex.
        5. Start the server: mix phx.server
      """)
    end

    :ok
  end

  # LiveSvelte is an optional dep of Caravela. Warn (don't fail) if the
  # consumer app doesn't have it yet — they may be adding it as part of
  # running this task.
  defp warn_if_live_svelte_missing do
    unless Code.ensure_loaded?(LiveSvelte) do
      Mix.shell().info(
        "note: LiveSvelte not loaded. Add {:live_svelte, \"~> 0.19\"} to mix.exs " <>
          "and run `mix deps.get` before booting the generated LiveViews."
      )
    end
  end
end
