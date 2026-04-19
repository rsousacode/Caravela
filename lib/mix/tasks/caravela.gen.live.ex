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

  Every LiveView mounts its Svelte component via `<LiveSvelte.svelte>`,
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
    * `--frontend MODE` — override the render transport for every
      entity in the domain. `MODE` is `live` (today's LiveView +
      WebSocket path) or `rest` (Inertia-style SSR via
      `caravela_svelte`). Without the flag, each entity's
      DSL-declared `frontend:` is used, defaulting to `:live`.
    * `--no-tests` — skip generating ExUnit + Vitest test skeletons.
      By default the generator emits one `<entity>_live_test.exs`,
      one `<entity>_controller_test.exs`, and one `*.test.ts`
      colocated next to each Svelte file. Tests use standard
      Phoenix / Vitest idioms and carry `# TODO:` lines where
      fixtures need to be filled in.

  Entities declared with `frontend: :rest` skip LiveView generation —
  Caravela prints a `caravela_rest` router snippet instead. Svelte
  components are emitted for both modes (the component contract is
  mode-agnostic).

  Regeneration preserves content below the `# --- CUSTOM ---` /
  `<!-- --- CUSTOM --- -->` marker in every file.
  """

  use Mix.Task

  alias Caravela.Gen.{
    LiveView,
    LiveViewTest,
    RestController,
    RestControllerTest,
    Svelte,
    SvelteTest
  }

  alias Caravela.MixHelpers
  alias Caravela.Schema.{Domain, Entity}

  @switches [
    dry_run: :boolean,
    output: :string,
    force: :boolean,
    with_domain: :boolean,
    frontend: :string,
    no_tests: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)
    domain = MixHelpers.load_domain!(args)
    domain = apply_frontend_override(domain, Keyword.get(opts, :frontend))
    root = Keyword.get(opts, :output, File.cwd!())
    with_domain? = Keyword.get(opts, :with_domain, false)
    force? = Keyword.get(opts, :force, false)

    warn_if_live_svelte_missing(domain)

    live_files = LiveView.render_all(domain, root: root, with_domain: with_domain?, force: force?)
    rest_files = RestController.render_all(domain, root: root, force: force?)
    svelte_files = Svelte.render_all(domain, root: root, force: force?)

    test_files =
      if Keyword.get(opts, :no_tests, false) do
        []
      else
        LiveViewTest.render_all(domain, root: root, force: force?) ++
          RestControllerTest.render_all(domain, root: root, force: force?) ++
          SvelteTest.render_all(domain, root: root, force: force?)
      end

    MixHelpers.write_files(
      live_files ++ rest_files ++ svelte_files ++ test_files,
      root,
      force?,
      Keyword.get(opts, :dry_run, false)
    )

    unless Keyword.get(opts, :dry_run, false) do
      if Enum.any?(domain.entities, &(&1.frontend == :rest)) do
        Mix.shell().info(router_hint(domain, rest?: true))
      else
        Mix.shell().info(router_hint(domain, rest?: false))
      end
    end

    :ok
  end

  # A single line the developer drops into their scope, instead of
  # pasting a snippet for every entity. `caravela_routes MyApp.Domains.X`
  # expands at compile time — see `Caravela.Router` for semantics.
  defp router_hint(%Domain{module: domain_module} = _domain, rest?: rest?) do
    base = """

    Routes — add one line to lib/<app>_web/router.ex:

        defmodule MyAppWeb.Router do
          use Phoenix.Router
          use Caravela.Router
    """

    rest_import =
      if rest? do
        "      import CaravelaSvelte.Router  # required for :rest entities\n"
      else
        ""
      end

    tail = """

          scope "/", MyAppWeb do
            pipe_through :browser
            caravela_routes #{inspect(domain_module)}
          end
        end
    """

    base <> rest_import <> tail <> next_steps(rest?)
  end

  defp next_steps(true = _rest?), do: rest_next_steps()
  defp next_steps(false = _rest?), do: live_next_steps()

  # Per-entity overrides keep `:rest` declarations even when the flag
  # requests `:live`; the flag only wins for entities that didn't
  # declare a mode explicitly. That way `--frontend rest` is a blanket
  # opt-in for unconfigured entities, not a silent override of
  # intentional declarations.
  defp apply_frontend_override(%Domain{} = domain, nil), do: domain

  defp apply_frontend_override(%Domain{} = domain, raw) when is_binary(raw) do
    mode =
      case raw do
        "live" -> :live
        "rest" -> :rest
        other -> Mix.raise("--frontend expects \"live\" or \"rest\", got: #{inspect(other)}")
      end

    entities =
      Enum.map(domain.entities, fn %Entity{} = entity -> %{entity | frontend: mode} end)

    %{domain | entities: entities}
  end

  defp live_next_steps do
    """

    Next steps:

      1. Add {:caravela_svelte, "~> 0.1"} to mix.exs (if you haven't already).
         Generated LiveViews mount Svelte components via CaravelaSvelte.svelte
         and delegate changeset errors to CaravelaSvelte.Caravela.errors/1.
      2. Install deps:  mix deps.get && cd assets && npm install && cd ..
      3. Wire CaravelaSvelte into assets/js/app.js (see caravela_svelte docs).
      4. Start the server: mix phx.server
    """
  end

  defp rest_next_steps do
    """

    Next steps:

      1. Add {:caravela_svelte, "~> 0.1"} to mix.exs. Both modes rely
         on caravela_svelte — :live mounts via CaravelaSvelte.svelte,
         :rest renders via CaravelaSvelte.render/3.
      2. Install deps:  mix deps.get && cd assets && npm install && cd ..
      3. Wire CaravelaSvelte into assets/js/app.js (see caravela_svelte docs).
      4. Review generated controllers under lib/<app>_web/controllers/ —
         they call CaravelaSvelte.Caravela.put_field_access/2 and
         errors/1 automatically. Custom logic goes below the
         `# --- CUSTOM ---` markers and is preserved on regeneration.
      5. Start the server: mix phx.server
    """
  end

  # caravela_svelte is the shared transport for both render modes. Warn
  # (don't fail) if the consumer app doesn't have it yet — they may be
  # adding it as part of running this task.
  defp warn_if_live_svelte_missing(%Domain{} = _domain) do
    unless Code.ensure_loaded?(CaravelaSvelte) do
      Mix.shell().info(
        "note: caravela_svelte not loaded. Add {:caravela_svelte, \"~> 0.1\"} " <>
          "to mix.exs and run `mix deps.get` before booting the generated " <>
          "LiveViews / controllers."
      )
    end
  end
end
