# Changelog

All notable changes to Caravela are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.13.0] — 2026-04-19

*Coverage + granularity. The generator now emits CI-ready test
skeletons (ExUnit + Vitest) for every entity it scaffolds, and
the frontend prop contract grows an `actions` channel so
generated UIs can gate Delete / Edit / Create buttons on the
policy engine — not just field visibility.*

### Added

- **`Caravela.Gen.LiveViewTest`** — emits one
  `<entity>_live_test.exs` per `:live` entity, covering
  Index / Show / Form with one `describe` per module and one
  test per action. Carries `# TODO:` pointers where app fixtures
  plug in.

- **`Caravela.Gen.RestControllerTest`** — emits one
  `<entity>_controller_test.exs` per `:rest` entity, covering
  every HTTP action with happy + error-path tests. Assertions on
  the structured-error shape from `Caravela.ChangesetTranslator`
  are pre-wired.

- **`Caravela.Gen.SvelteTest`** — Vitest +
  `@testing-library/svelte` smoke tests colocated with every
  generated Svelte file (`BookIndex.test.ts` next to
  `BookIndex.svelte`). Tests mount the component with minimally
  valid props and cover the structured-error prop shape.

- **`--no-tests` flag on `mix caravela.gen.live`** — opt out of
  test generation entirely. The default is to emit tests.

- **`action_access/2` and `action_access/3` on the generated
  context** — return `%{create: bool, update: bool |
  :per_record, delete: bool | :per_record}` based on the policy
  block. `/3` resolves `:per_record` gates against a specific
  record for per-row decisions in index templates.

- **`<Entity>Actions` TypeScript interface** — emitted in the
  shared types file alongside `<Entity>FieldAccess`. Arity-2
  gates type as `boolean | 'per_record'` so the frontend
  knows when to call back per row.

- **`actions` prop on every generated Svelte component** —
  alongside `field_access`. `svelte_index.eex` now conditionally
  renders the Delete / Edit / New buttons on
  `actions.delete === true` / `actions.update === true` /
  `actions.create !== false`. Users who want unconditional
  rendering can remove the `{#if}` wrappers below the CUSTOM
  marker.

### Changed

- **`mix caravela.gen.live` emits tests by default.** Running
  against a domain now produces ~2× the files (tests +
  implementation). Pass `--no-tests` to match pre-0.13 behavior.

- **Generated LiveViews and REST controllers assign `:actions`**
  alongside `:field_access` and pass both to the Svelte
  component as separate props. Existing Svelte components that
  only read `field_access` keep working; adding
  `actions.delete === true` gating is opt-in.

### Migration — v0.12 → v0.13

- Re-running `mix caravela.gen.live` on an existing domain adds
  the test files and rewrites the templates to thread
  `actions`. The `# --- CUSTOM ---` markers are preserved, so
  handwritten tweaks survive.
- Add `vitest` and `@testing-library/svelte` as dev deps in
  `assets/package.json` to run the generated Svelte tests —
  Caravela doesn't manage `package.json` for you.
- Existing Svelte components keep working without `actions`
  (default is permissive). To gate buttons on policy, read
  `actions.delete === true` / `actions.update === true` and
  render conditionally.

## [0.12.0] — 2026-04-19

*Two API-contract upgrades that make Caravela-generated frontends
adoption-ready for real teams: a compile-time router macro that
replaces the paste-snippet workflow, and a structured /
Gettext-ready changeset error shape.*

### Added

- **`Caravela.Router` + `caravela_routes/1,2`** — drop one line into
  `router.ex` and every route for every entity in a domain is
  registered at compile time. `:live` entities expand into
  `live "/<plural>", <Entity>Live.<Kind>` calls; `:rest` entities
  expand into `caravela_rest "/<plural>", <Entity>Controller`
  (with `realtime: true` appended when the entity opts in).
  Version-aware: respects `version "v1"` by inserting the version
  segment into module aliases so Phoenix scope-alias resolution
  still works.

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        use Caravela.Router
        import CaravelaSvelte.Router

        scope "/", MyAppWeb.Library do
          pipe_through :browser
          caravela_routes MyApp.Domains.Library
        end
      end

  Accepts a `:session` option forwarded to Phoenix's
  `live_session/3` so a group of `:live` entities can share an
  `on_mount` hook without boilerplate.

- **`Caravela.ChangesetTranslator`** — returns
  `%{field => [%{code: atom, params: map, message: String.t}]}`
  instead of the flat `%{field => [msg]}` Phoenix ships by
  default. Frontends key on `:code` for localization, interpolate
  `:params` into their own translation template, and fall back to
  `:message` when no frontend translation exists.

  Gettext integration is one config line:

      config :caravela, :changeset_translator, MyAppWeb.Gettext

  Caravela calls the backend's `dgettext/3` and `dngettext/5`
  (plural forms via Ecto's `:count` option) — the same contract
  Phoenix's own `ErrorHelpers.translate_error/1` uses, so existing
  `priv/gettext/<locale>/LC_MESSAGES/errors.po` locale files work
  unchanged.

### Changed

- **Generated LiveView forms and REST controllers** now produce
  the structured error shape via `Caravela.ChangesetTranslator`,
  shared across both transports. Replaces the flat
  `CaravelaSvelte.Caravela.errors/1` delegation added in v0.11 —
  that helper stays in `caravela_svelte` for backward compat, but
  Caravela-generated code no longer uses it.

- **`mix caravela.gen.live` no longer prints a paste-snippet for
  the router.** It prints a minimal one-line hint pointing at the
  `caravela_routes` macro. Existing apps that pasted snippets
  manually keep working; the generator just stops nagging.

### Migration — v0.11 → v0.12

- Replace any pasted router snippet with `use Caravela.Router` +
  `caravela_routes <DomainModule>`. The macro-expanded routes
  match what v0.11 printed, so URL paths and module names don't
  change.
- Frontend consumers that expect the old `%{field => [msg]}`
  error shape need to adapt. The new payload is
  `%{field => [%{code, params, message}]}`. Most Svelte form
  helpers only need to read `err.message` — a one-line change.
  For i18n, read `err.code` + `err.params` instead.
- To stay on English-only Phoenix defaults, no config is needed —
  the translator falls back to interpolating `%{param}`
  placeholders when no `:changeset_translator` is configured.

## [0.11.0] — 2026-04-19

*Ships the Caravela ↔ `caravela_svelte` integration
([phase_c1_generator_integration.md](https://github.com/rsousacode/caravela-plan/blob/main/render_modes/phase_c1_generator_integration.md)).
Entities now declare `frontend: :rest` (optionally with
`realtime: true`); the generator branches to emit either a
LiveView tree (`:live`) or a Phoenix controller (`:rest`), both
targeting `caravela_svelte`'s shared client bundle. Generated
code delegates field-access and changeset-error handling to
`CaravelaSvelte.Caravela` helpers, so the same prop shape
reaches every Svelte component regardless of transport.*

### Added

- **`entity :name, frontend: :rest | :live do … end`** — new
  entity-level option on the `Caravela.Domain` DSL. Defaults to
  `:live`, so existing domains are unaffected. `:rest` marks the
  entity for rendering through `caravela_svelte`'s HTTP/Inertia
  transport instead of LiveView + WebSocket. Invalid values and
  unknown entity options raise `Caravela.DSLError` with
  actionable suggestions.

- **`entity :name, frontend: :rest, realtime: true do … end`** —
  opts the entity into SSE-driven real-time updates on top of
  the `:rest` transport. Generated controllers call
  `CaravelaSvelte.Caravela.broadcast_patch/3` on create, update,
  and delete, scoped per-actor via `entity_topic/2`. Rejected
  with a clear error on `:live` entities (LiveView's WebSocket
  already covers that case).

- **`Caravela.Schema.Entity{:frontend, :realtime?}`** — IR
  carries both the declared transport and the realtime flag.
  Exposed as `entity.frontend` (string) and `entity.realtime`
  (boolean) on `Caravela.IR.of/1` output, visible through the
  `caravela__describe_entity` MCP tool response.

- **`Caravela.Gen.RestController`** — new generator. Emits one
  Phoenix controller per `frontend: :rest` entity at
  `lib/<app>_web/controllers/<entity>_controller.ex`. Renders
  Svelte components through `CaravelaSvelte.render/3`; wires
  `CaravelaSvelte.Caravela.put_field_access/2` and
  `CaravelaSvelte.Caravela.errors/1` on every action; adds
  `broadcast_patch/3` call sites when `realtime: true`.
  Custom code below `# --- CUSTOM ---` markers is preserved on
  regeneration (same convention as the rest of Caravela's
  generators).

- **`mix caravela.gen.live --frontend <mode>`** — blanket
  override flag. `--frontend rest` or `--frontend live` applies
  to every entity in the domain, ignoring declared values. Useful
  for a quick preview of generator output for a different mode
  without editing the DSL.

### Changed

- **`Caravela.Gen.LiveView.render_all/2`** now skips entities
  whose `frontend` is `:rest`. A domain where every entity is
  `:rest` produces zero LiveView files.

- **`Caravela.Gen.LiveRoute.render/1`** now emits up to two
  router blocks per domain: a `live …` block for `:live`
  entities (as before) and a `caravela_rest …` block for
  `:rest` entities. Entities declared with `realtime: true`
  get `realtime: true` appended to their `caravela_rest` line
  so the router registers the SSE endpoint. The emitted
  snippet mentions the required
  `import CaravelaSvelte.Router`.

- **`mix caravela.gen.live`** now invokes `RestController` in
  addition to `LiveView` and `Svelte`, so a single command
  produces the full frontend layer (controllers for `:rest`
  entities, LiveViews for `:live` entities, Svelte components
  for both). The next-steps message adapts to whichever modes
  are present.

- **`caravela__describe_frontend_mode`** — new MCP tool. Reports
  the render-mode configuration for a domain (or a single entity
  when `entity: "..."` is provided): `frontend`, `realtime`, and
  short transport-specific notes an LLM host can use before
  suggesting code. Registered in `Caravela.MCP.Tool.registry/0`.

- **`@caravela-*` metadata header on generated Svelte files** —
  every `Book{Index,Show,Form}.svelte` now carries
  `@caravela-entity`, `@caravela-mode`, and (when applicable)
  `@caravela-realtime` tags in its top-of-file HTML comment. Lets
  the new MCP tool and any other static analysis pick up the
  render mode from the file without re-parsing the DSL.

- **`caravela_svelte` as optional dep** (`~> 0.1`). Caravela does
  not force the dep on consumers, but generated code references
  `CaravelaSvelte.*` modules, so apps using the generators must
  now pull in `{:caravela_svelte, "~> 0.1"}` alongside Caravela.

### Changed

- **Generated LiveViews now mount via `<CaravelaSvelte.svelte>`,
  not `<LiveSvelte.svelte>`**. The prop and slot contract is
  identical, but both render modes now flow through the same
  client bundle (`@caravela/svelte`). Existing apps that
  regenerate must add `{:caravela_svelte, "~> 0.1"}` to `mix.exs`
  — see the new next-steps output from `mix caravela.gen.live`.

- **Generated LiveView forms delegate `changeset_errors/1` to
  `CaravelaSvelte.Caravela.errors/1`** — a single authoritative
  implementation shared with the `:rest` controller template, so
  error shapes stay aligned across modes.

- **`mix caravela.gen.live` next-steps output** was rewritten for
  both modes to reference `caravela_svelte` instead of
  `live_svelte`. The cold-start warning when the dep is missing
  now prints when `CaravelaSvelte` isn't loaded, regardless of
  which modes are in play.

### Deferred (post-1.0 ergonomics)

- `Caravela.Gen.svelte_component/2` / igniter recipe for
  scaffolding a single Svelte file per entity. Open question —
  whether this belongs here or in `caravela_svelte`.
- Regenerating `caravela_demo`'s snapshot fixtures to use the
  new `CaravelaSvelte.svelte` mount. Done in the demo repo, not
  this package.

## [0.10.0] — 2026-04-19

*Ships §9 of [llm_friendliness.md](https://github.com/rsousacode/caravela-plan/blob/main/phoenix/llm_friendliness.md) —
the MCP server. An LLM host (Claude Code, Cursor, Zed) can now call
Caravela tools directly instead of guessing DSL syntax. Shipped as
part of the main `caravela` package (not a separate repo) because
every tool is a thin wrapper over Caravela internals shipped in
0.9.x.*

### Added

- **`Caravela.MCP`** — [Model Context Protocol](https://modelcontextprotocol.io)
  server over stdio transport. JSON-RPC 2.0 framing, one message
  per line. Protocol version `2024-11-05`.

- **`mix caravela.mcp`** — launch the server in a Caravela project.
  Compiles the project first (so domains are loadable for
  introspection) and serves on stdin/stdout. Intended to be spawned
  by an MCP host:

      // Claude Code ~/.claude/claude_desktop_config.json
      {
        "mcpServers": {
          "caravela": {
            "command": "mix",
            "args": ["caravela.mcp"],
            "cwd": "/absolute/path/to/your/project"
          }
        }
      }

- **Four tools:**
  - `caravela__describe_domain` — full IR for a domain module.
  - `caravela__list_entities` — entity names (fast discovery).
  - `caravela__describe_entity` — single entity + inbound / outbound
    relations.
  - `caravela__validate_dsl` — compile a candidate DSL source and
    return either the resulting IR (on success) or a structured
    `DSLError` / `GenError` / `CompileError` payload (on failure).
    Rescues all exceptions — the tool never crashes the server.

- **`Caravela.MCP.Tool`** behaviour. Third-party tools slot into the
  same registry; shipped tools are all first-class citizens. See
  `Caravela.MCP.Tool.ListEntities` for a minimal reference
  implementation.

- **`Caravela.MCP.Protocol`** — JSON-RPC 2.0 builders (`response/2`,
  `error/4`, `method_not_found/2`, etc.) and encode / decode for
  stdio framing.

- **`Caravela.MCP.Router`** — pure method dispatch (map → map).
  `Caravela.MCP.Server` wraps it with the stdio IO loop, split so
  tests exercise the router without touching real IO.

### Notes

- **Stdio transport only in 0.10.** HTTP (for remote / team MCP)
  and auth gating land in 1.1 per the plan.
- **`caravela__validate_dsl` compiles arbitrary Elixir source.**
  Safe on localhost stdio (the host supplying the source is the
  user's own LLM client running on their machine). When HTTP
  transport arrives, this tool MUST move behind auth + a proper
  sandbox. Documented in the tool's moduledoc.
- **Specs enforced.** All 10 new MCP modules (`Caravela.MCP`,
  `Caravela.MCP.Protocol`, `Caravela.MCP.Tool`, `Caravela.MCP.Router`,
  `Caravela.MCP.Server`, plus the 4 tool modules) are on the
  `.credo.exs` allowlist — every public function carries a
  `@spec`, enforced by CI.
- **42 new tests**: protocol round-trip, router dispatch, each tool's
  happy + error paths, full stdio handshake round-trip via
  `StringIO`. 462 total now.

## [0.9.2] — 2026-04-19

*Kicks off the §10 spec pass from
[llm_friendliness.md](https://github.com/rsousacode/caravela-plan/blob/main/phoenix/llm_friendliness.md) —
every public function on the stable-API allowlist now carries a
`@spec`. Wires Credo into CI as a hard gate so new public functions
without specs fail the pipeline.*

### Added

- **`@spec` on every public function** in ten stable-API modules:
  `Caravela.IR`, `Caravela.Errors`, `Caravela.Error`,
  `Caravela.Types`, `Caravela.Naming`, `Caravela.Tenant`,
  `Caravela.Auth`, `Caravela.Policy`, `Caravela.Schema`,
  `Caravela.Gen.Custom`. 85 specs added across the set.

- **Type aliases** where the same shape recurred:
  - `Caravela.Naming.domain_or_module :: Domain.t() | module()`
  - `Caravela.Naming.entity_name :: atom()`
  - `Caravela.Naming.kind :: :index | :show | :form`
  - `Caravela.Types.dsl_type :: atom()`
  - `Caravela.Gen.Custom.style :: :elixir | :ts | :svelte`

- **Credo dep** (`~> 1.7`, dev/test only) + `.credo.exs` with
  `Credo.Check.Readability.Specs` enabled and scoped via
  `files.included` to the stable-API allowlist. Running a plain
  `mix credo --strict` locally also surfaces advisory hygiene
  checks (nesting depth, function complexity) that aren't hard-
  gated yet.

- **CI hard gate**: `.github/workflows/ci.yml` now runs
  `mix credo --strict --only Readability.Specs` between compile
  and test. New public functions added to allowlisted modules
  without a `@spec` fail the pipeline. Modules outside the
  allowlist (mix tasks, generator internals, `Live.*` macros) are
  intentionally excluded until they stabilize — see the comments
  in `.credo.exs` for the rationale.

### Notes

- The allowlist grows as modules stabilize. Intended pattern for
  future additions: add the file path to `.credo.exs`, run
  `mix credo --strict --only Readability.Specs`, add the missing
  specs it flags, done. No per-module config beyond the include list.
- This is **presence** enforcement (every public fn has a spec),
  not **correctness** enforcement. Spec correctness is Dialyzer's
  job; wiring Dialyzer into CI is deferred to the 1.1 phase per
  the LLM plan.

## [0.9.1] — 2026-04-19

*Second pass of the LLM-friendliness roadmap
([llm_friendliness.md](https://github.com/rsousacode/caravela-plan/blob/main/phoenix/llm_friendliness.md)).
Completes the §4 error-message rewrite across every remaining DSL and
generator raise site, and ships the §10 `mix caravela.info` companion
to `mix caravela.ir`.*

### Added

- **`mix caravela.info`** — human-readable summary of a compiled
  domain. Prints domain-level flags (multi-tenant, default policy,
  api version), a per-entity block with fields / relations / policy
  summary / auth config, and a footer with hook + relation counts.
  Companion to `mix caravela.ir` (which emits JSON); use `info` for
  humans scanning "what's in this domain?" and `ir` for tooling
  consuming the IR programmatically.

      mix caravela.info MyApp.Domains.Library
      mix caravela.info MyApp.Domains.Library --no-color   # for CI / piping

  Exposed as a library call via `Mix.Tasks.Caravela.Info.render/2`
  so tests and external tools can consume the same rendering
  without shelling out.

### Changed (breaking)

- **Remaining DSL error sites migrated from `ArgumentError` /
  `CompileError` to `Caravela.DSLError`.** In particular every
  raise routed through `Caravela.Domain.compile_error!/2` and
  `Caravela.Compiler.compile_error!/2` now carries the structured
  four-part message shape. Covers:
  - Policy DSL: duplicate scope rules, malformed `field :x, opts`
    inside `policy`, `policy` with a non-atom entity, action-gate
    arity validation.
  - Authenticatable DSL: missing strategies, missing email field
    for `:password`, manual declaration of auto-injected fields,
    invalid `api_token :ttl` shape, multiple authenticatable
    entities per domain.
  - Live runtime DSL: `Caravela.Live.Domain.on_event` / `updater`
    arity + shape errors.
  - Live form DSL: `Caravela.Live.Form.visible` / `validate_async`
    field / arity / opts errors.
  - Compiler-level validations: entity / field / relation /
    hook cross-checks emitted from `Caravela.Compiler`.

- **Generator error sites migrated to `Caravela.GenError`.** The
  three `Gen.Auth*` "no entity with an `authenticatable` block"
  raises now carry a structured message with a canonical fix
  suggestion.

  Tests asserting `ArgumentError` or `CompileError` against any of
  these surfaces need to switch to `Caravela.DSLError` or
  `Caravela.GenError`. The regex from the old assertion still
  matches the new message.

### Kept as `ArgumentError` (intentionally)

- `Caravela.IR.of/1` bad-argument errors (runtime API, not DSL).
- `Caravela.Flow.start/3` runtime "no flow named" lookup failures.
- `Caravela.Live.Template` runtime updater-not-found / arity-mismatch
  errors (not compile-time — fire when `apply_updater` is called
  with a bad name at runtime).

These sites are documented in-code; they don't benefit from the
structured format since there's no compile-time suggestion to make.

### Fixed

- Pre-existing `ArgumentError` assertions in the test suite updated
  for 9 sites that exercised migrated paths. No behavior change;
  assertions now name the correct exception type.

## [0.9.0] — 2026-04-19

*First phase of the LLM-friendliness roadmap
([llm_friendliness.md](https://github.com/rsousacode/caravela-plan/blob/main/phoenix/llm_friendliness.md)).
Delivers structured errors, a unified validation command, and a
public IR export — the "close the iteration loop" half of the plan.
Eval harness, natural-language scaffolder, and MCP server land in
subsequent releases.*

### Added

- **`Caravela.IR`** — public, JSON-serializable view of a compiled
  domain. Call `Caravela.IR.of(MyApp.Domains.Library)` to get a plain
  map of entities, fields, relations, policies, hooks, and auth
  config. Anonymous functions inside policies are not included; only
  their metadata (existence, arity, target). The shape is semver-stable
  starting from this release.

- **`mix caravela.ir`** — print the IR as JSON (or write it to a
  file). Intended for consumption by editors, LLMs, and external
  tooling that wants a structured view of the domain without parsing
  Elixir source.

      mix caravela.ir MyApp.Domains.Library > library.json
      mix caravela.ir MyApp.Domains.Library --output docs/library.json
      mix caravela.ir MyApp.Domains.Library --no-pretty

- **`mix caravela.check`** — single-command validation oracle.
  Compiles the project, discovers every module using `Caravela.Domain`,
  runs all applicable generators in dry-run mode, and optionally
  runs `mix test` (`--tests`) and `mix dialyzer` (`--dialyzer`).
  Exits 0 on green, non-zero with a per-domain / per-generator
  summary otherwise. Targeted at LLM iteration loops and CI — one
  command, one pass/fail signal.

      mix caravela.check
      mix caravela.check --only MyApp.Domains.Library
      mix caravela.check --tests --dialyzer
      mix caravela.check --quiet

- **`Caravela.DSLError` / `Caravela.GenError`** — structured
  exceptions with a four-part message: *what went wrong*, *what
  Caravela got* (code snippet), *suggested fix*, *docs URL*. Every
  migrated DSL error now spells out both the problem and a canonical
  example of the right shape. `Caravela.Errors.dsl/2` and
  `snippet_from_env/1` are convenience helpers for macro authors.

  Example rendered output:

      ** (Caravela.DSLError) `scope` must be called inside a `policy` block

         Suggestion:
             policy :books do
               scope fn q, actor -> where(q, [b], b.tenant_id == ^actor.tenant_id) end
             end

         See: https://hexdocs.pm/caravela/policies.html#scope

### Changed (breaking)

- **DSL errors now raise `Caravela.DSLError` instead of
  `ArgumentError`.** Migrated sites: `default_policy` option,
  `version` option, `scope`/`allow`/`field` inside policy blocks,
  every `authenticatable` sub-macro (`strategy`, `session`,
  `confirm`, `reset`, hook blocks, unknown strategy names), `flow`
  name validation, and `Caravela.Types.ecto_type/1` /
  `postgres_type/1` on unknown field types.

  If you had `assert_raise ArgumentError` tests against any of these
  surfaces, update to `assert_raise Caravela.DSLError`. The
  structured message is strictly more informative; the regex from
  the old assertion will still match the new message.

- **`Caravela.Gen.SvelteForm.render/2`** raises `Caravela.GenError`
  on a missing-entity reference (previously `ArgumentError`) and
  includes the list of known entities in the suggestion.

### Migration

No source changes required for domain files; the migration is only
visible if you had tests asserting on the old exception type. Run
`mix caravela.check` after upgrading to confirm everything parses
cleanly.

Not every `raise ArgumentError` site has been migrated yet — this
release covers the DSL and generator surfaces that users hit most
often. Runtime `Caravela.Live.*` errors and a handful of generator
edge cases still raise `ArgumentError` and will migrate
incrementally in 0.9.x / 1.0.

## [0.8.1] — 2026-04-19

### Added

- **Checksum header on every generated file.** Every regenerable file
  now starts with a line of the form

      # caravela-gen: generator=context version=0.8.1 above_sha256=<hex>

  (or the `//`- / `<!-- -->`-wrapped equivalent for TS and Svelte
  outputs). The sha256 covers the content above the `CUSTOM` marker.
  On regeneration the hash is recomputed against what's on disk; if
  the above-marker region was edited by hand, the generator aborts
  via `Mix.raise/1` and points the user at three remediation steps
  (move edits below the marker, re-run with `--force`, or `--dry-run`
  to inspect). Named-block bodies are *excluded* from the hash, so
  edits inside a per-function `# --- CUSTOM :name ---` block don't
  trigger a mismatch.

- **Per-function named CUSTOM blocks.** Every Elixir-style generator
  now emits pairs like

      # --- CUSTOM :list_books ---
      # --- END :list_books ---

  at natural extension points — after each CRUD function in the
  context, after each action in the controller, around the changeset
  in the Ecto schema, per entity in the GraphQL types/queries/
  mutations, after `mount/3` and before `render/3` in LiveViews, and
  around register/login/logout/reset/confirm in the auth context.
  Regeneration merges content from these blocks by name: add user
  code inside `:list_books`, regen freely, code is preserved.

- **Orphan detection.** If a named block exists on disk but no
  longer has a counterpart in the generator output (e.g. an entity
  was renamed), regen emits a `Mix.shell/0` warning listing every
  orphan name and discards the content. The file-tail `CUSTOM`
  marker's contents still carry through for freeform user code.

- **`--force` flag on every `mix caravela.gen.*` task** now threads
  through to `Caravela.Gen.Custom.verify_existing!/2`, printing a
  yellow warning with the stored/current hashes and proceeding to
  overwrite. Previously the flag only controlled the file-exists
  prompt.

### Fixed

- **Merge bug when the marker string appeared inside a docstring.**
  The old `String.split(…, marker, parts: 2)` cut on the first
  occurrence, which in Elixir templates was the moduledoc prose
  (`Custom code placed below the \`# --- CUSTOM ---\` marker is
  preserved.`). Regeneration then produced garbled output for any
  template whose moduledoc mentioned the marker. `Gen.Custom.merge/3`
  and the hash splitter now use `:binary.matches/2 |> List.last/1`
  so they always latch onto the real tail marker.

### Changed

- `Caravela.Gen.Custom` rewritten from the file-tail-only merge
  helper into a full verification + merge pipeline with pluggable
  comment styles (`:elixir`, `:ts`, `:svelte`). Public API additions:
  `named_empty/2`, `extract_named_blocks/1`, `merge_named/3`,
  `stamp_header/2`, `verify_existing!/2`, `verify_contents/2`,
  `parse_header_line/2`. `marker/1` now takes an optional style.

- The ad-hoc `@ts_marker` / `@svelte_marker` / `merge_ts/2` /
  `merge_svelte/2` duplicated across `Gen.Svelte`, `Gen.SvelteForm`,
  and `Gen.AuthSvelte` has been removed — all three now delegate to
  `Caravela.Gen.Custom.merge_with_file/3` with `style: :ts` or
  `style: :svelte`.

### Migration

No source changes required. The first time you run any
`mix caravela.gen.*` task after upgrading, Caravela treats existing
files as "unheadered legacy" and silently stamps a header. Subsequent
regens enforce the checksum. If you had been editing *above* the
`# --- CUSTOM ---` marker, the first post-upgrade regen after that
edit will abort with a clear message; re-run with `--force` (to
overwrite) or move the edits below the marker (to keep them).

## [0.8.0] — 2026-04-18

### Changed (breaking)

- **Deny-by-default policy fallback.** Domains now default to
  `default_policy: :deny`. Any entity without a declared `policy`
  block has its scope filtered to zero rows, every field masked out,
  and every write denied. The prior permissive behavior is still
  available as `use Caravela.Domain, default_policy: :allow`.

  Motivation: a forgotten policy on a new entity used to silently
  ship unscoped data. With deny-by-default, the same forgetful moment
  produces an obviously-empty list instead of a leak. If you want
  per-entity control, add a minimal `policy :entity do scope fn q, _ ->
  q end end` — declaring *any* policy block for an entity makes its
  undeclared rule types permissive for that entity (the "per-entity
  fallback" tier of the cascade).

- **Generated `compute_field_access/2` routes every field through the
  policy dispatch function.** Previously, unruled fields were hardcoded
  to literal `true` in the generated context; the hardcoding hid the
  domain-level `default_policy` from reaching them. Now every field
  calls `__caravela_policy_field_visible__/3` and the clause cascade
  on the domain module (specific rule → per-entity fallback →
  module-level fallback) decides the result. No visible runtime
  difference for domains without policies that stayed on `:allow`.

### Added

- `Caravela.Schema.Domain.default_policy/1` helper returning `:deny`
  or `:allow`.
- `use Caravela.Domain` now imports `Ecto.Query.where/3` and
  `Ecto.Query.from/2` into the calling module, so `scope fn q, actor ->
  where(q, [b], b.published) end` works without a manual
  `import Ecto.Query` (previously a silent runtime failure).

### Migration

- If any of your domains rely on the old permissive fallback, add
  `default_policy: :allow` to the `use Caravela.Domain` call.
- If you want to tighten up an existing domain, remove the
  `:allow` option and add a `policy :entity do …` block per entity.
  Missing rule types inside the block stay permissive, so partial
  declarations are safe.

## [0.7.0] — 2026-04-18

### Removed (breaking)

- `can_read` / `can_create` / `can_update` / `can_delete` macros and
  the `__caravela_permission__/2,3,4` dispatch functions they emitted.
  These ran in parallel with phase 9's `policy` blocks, producing an
  implicit intersection of two authorization systems with no
  documentation of the interaction. Since the library has no published
  users yet, the simpler path was to delete outright instead of
  deprecating.
- `Caravela.Schema.Permission` struct and the `permissions` field on
  `Caravela.Schema.Domain`.
- Generated context helpers `apply_read_permission/3`,
  `authorize_create/2`, `authorize_update/3`, `authorize_delete/3`.
  Read paths now go through `apply_scope/3`; write paths go through
  `policy_authorize/3,4`. Both resolve against the `policy` block's
  compiled dispatch functions on the domain module.

### Migration

Port every `can_*` declaration into a `policy :entity do … end` block.
Rule functions now receive the **actor** (`context.current_user`),
not the raw context map:

```elixir
# before
can_read   :books, fn q, ctx -> where(q, [b], b.published) end
can_create :books, fn ctx -> ctx.current_user.role == :admin end
can_update :books, fn b, ctx -> ctx.current_user.id == b.author_id end
can_delete :books, fn _b, ctx -> ctx.current_user.role == :admin end

# after
policy :books do
  scope fn q, actor -> if actor.role == :admin, do: q, else: where(q, [b], b.published) end

  allow :create, fn actor -> actor.role == :admin end
  allow :update, fn actor, record -> actor.id == record.author_id end
  allow :delete, fn actor -> actor.role == :admin end
end
```

The generated context is the one that did the dispatch, so the only
runtime change is the shape of the predicate's first argument.

## [0.6.0] — 2026-04-18

### Added

- **Phase 7 — `authenticatable` trait.** Declare `authenticatable` on
  an entity and `mix caravela.gen.auth` emits the full email/password
  + API-token server stack: auth context (register/login/logout,
  sessions with TTL + `remember_me` + `max_sessions`, email
  confirmation, password reset, scoped API tokens), session schema,
  Plug pipeline (`fetch_current_user`, `require_auth`, `require_role`,
  `require_scope`), LiveView `on_mount` hooks, auth controller, and a
  session-tokens migration. `on_register` / `on_login` lifecycle
  callbacks. Validated compile-time: one authenticatable entity per
  domain, `:email` field required when `:password` strategy is used,
  no collision with auto-injected `hashed_password` / `confirmed_at` /
  `api_tokens`.
- **Phase 8 — LiveSvelte auth UI.** `mix caravela.gen.auth` also
  emits six Svelte components — `LoginForm`, `RegisterForm` (inputs
  derived from the user entity's public fields), `ResetPasswordForm`
  (two-phase: request + confirm), `ConfirmEmail`, `TokenManager`
  (scopes + `max_tokens` reflected from the DSL), `SessionList` —
  plus matching LiveView pages (`AuthLive.*`), and prints a ready-to-
  paste router snippet (public auth routes + authenticated
  `live_session` with `on_mount` hook + authenticated API scope).
  Generated User schema gains `registration_changeset`,
  `password_changeset`, `api_tokens_changeset`, `confirm_changeset`
  with Argon2 password hashing. TS types add `CurrentUser`, `ApiToken`,
  `Session`. Flags `--skip-ui` / `--skip-router` for server-only use.
- **Phase 9 — Triple-target policies.** New `policy :entity do …
  end` block in the domain DSL compiles a single declaration into
  three simultaneous enforcement layers: (1) Ecto `WHERE` clauses via
  `scope fn query, actor -> query end`, (2) field projection that
  strips invisible fields from every `list_*` / `get_*` response via
  `field :name, visible: fn actor[, record] -> bool end`, and (3) a
  typed `field_access` Svelte prop (`<Entity>FieldAccess` TypeScript
  interface) that the generated index/show/form components use to
  gate ruled columns, fields, and inputs with `{#if field_access.*}`.
  `allow :create | :update | :delete, fn actor[, record] -> bool end`
  extends the Phase 2 permission check with record-aware gates.
  Arity-1 rules resolve to booleans at request time; arity-2 rules
  resolve to a `'per_record'` sentinel and evaluate per row, with
  denied fields served as `null`. Unpolicied entities fall through to
  permissive defaults — fully backward-compatible with existing
  `can_*` hooks.
- `Caravela.Policy` module with `Entry`, `Scope`, `FieldRule`,
  `ActionGate` IR structs, and `Domain.policy_for/2` / `auth_entity/1`
  lookups.
- New guides: [docs/auth.md](docs/auth.md),
  [docs/policies.md](docs/policies.md).

### Changed

- Generated TypeScript type imports are now combined
  (`import type { Book, BookFieldAccess, LiveHandle } from '…'`)
  instead of one line per type.
- Generated `User` Ecto schema excludes `hashed_password`,
  `confirmed_at`, `api_tokens` from the generic `cast` path — they
  flow only through the specialised changesets above.
- `Caravela.Gen.Svelte.public_fields_for/1` also strips credential
  fields (`hashed_password`, `api_tokens`) from the Svelte-bound
  representation, so they can never reach the browser through either
  the typed TS interface or a CRUD form.

## [0.5.3] — 2026-04-18

### Added

- `Caravela.Error` — uniform error struct (`:unauthorized`,
  `:not_found`, `:invalid`, `:internal`) so upstream code can pattern-
  match once instead of threading the four shapes individually
  generated contexts return today. `wrap/1` lifts a plain reason into
  the struct; `message/1` renders a default flash phrase.
- `Caravela.Live.OnMount` — `on_mount` callback that assigns a
  `:context` map (`%{current_user, tenant}`) to the socket, so
  LiveViews can read from `@context` instead of each re-rolling
  `build_context/1`. `put/3` exposes a merge helper for downstream
  hooks.
- `Caravela.Gen.Context` now emits a `delete_<entity>(id, context)`
  variant alongside the existing `(struct, context)` form, so
  delete-from-index is one round trip (`get |> delete`). Returns
  `{:error, :not_found}` when the id is missing or hidden. The
  generated index LiveView uses the shorter path.

### Changed

- Generated `--with-domain` form LiveView now passes keyword args
  (`apply_updater(:load, entity: e, attrs: a, errors: er)` and
  `apply_updater(:put_attr, field: f, value: v)`) instead of anonymous
  tuples. The emitted `FormDomain` matches with `Keyword.fetch!/2`.
  Self-documenting and survives adding a new field without silently
  shifting positional args.

### Fixed

- Generated Svelte components now destructure the `live` hook handle
  LiveSvelte ≥ 0.18 actually injects, and call `live.pushEvent(...)`.
  Previously every generated component pulled `pushEvent` out of
  `$props()` — which never existed — so every Edit / Delete / New /
  Save / Cancel button silently threw `TypeError: pushEvent is not a
  function` and the corresponding server event never fired.
- `Caravela.Gen.Context` now emits `preload([:assoc, …])` on
  `list_*` / `get_*` / `get_*!` for every `belongs_to` association
  declared on the entity. Rows no longer ship the raw
  `%Ecto.Association.NotLoaded{}` sentinel (with `__owner__` /
  `__field__` / `__cardinality__` internals) to the browser, and
  dereferencing `book.author.name` on the Svelte side now works
  without a hand-written preload.
- Generated `--with-domain` and plain form LiveViews replace the
  `Map.from_struct(entity) |> Map.drop([:__meta__])` attrs seed with a
  narrow `entity_attrs/1` helper that keeps only the declared entity
  fields and normalises `%Decimal{}` values to their string form. Form
  inputs on an Edit screen no longer render `[object Object]` for
  decimal / money fields, and the attrs map has stable types across
  validate round-trips.

### Changed

- Generated LiveView `render/1` now calls `<LiveSvelte.svelte>`
  (passing `socket={@socket}`) instead of the deprecated
  `<LiveSvelte.render>` component. Silences the deprecation warning
  on every request and re-enables SSR for connected sockets.
- New `Caravela.Live.Encoders` module provides `LiveSvelte.Encoder`
  protocol implementations for `Decimal` (→ normalised string) and
  `Ecto.Association.NotLoaded` (→ `nil`), guarded so the file compiles
  even when LiveSvelte < 0.18 is in use (the protocol is absent there).
- Generated TypeScript types file now exports a `LiveHandle` interface
  describing `live.pushEvent` / `pushEventTo` / `handleEvent`, which
  every generated component imports for its `live` prop.

## [0.5.2] — 2026-04-18

### Changed

- Generated Svelte components and doc examples now use Svelte 5's
  `$props()` rune for prop declarations instead of the deprecated
  `export let` syntax. LiveSvelte 0.19 ships with Svelte 5 runtime;
  `export let` still worked but produced compile-time warnings.

## [0.5.1] — 2026-04-18

### Fixed

- Generated `--with-domain` form LiveView no longer crashes with
  `KeyError :errors` on mount. The template now seeds the domain's
  default state (via `Caravela.Live.Template.__assign_defaults__/2`)
  before the first `apply_updater(:load, ...)` call.
- `Caravela.Flow.Runner` — `race` advances as soon as the first task
  resolves instead of waiting the full timeout (was relying on
  `Task.yield_many/2`'s "wait for all, take first").
- `Caravela.Gen.Context` emits simplified `authorize_*` / `run_delete_hook`
  functions when no corresponding `can_*` / `on_delete` rule is
  declared, eliminating the "clause will never match" warnings that
  appeared on every compile of a fresh CRUD generation.
- `Caravela.Gen.SvelteForm` and `Caravela.Gen.Svelte` now emit Svelte 5
  event attribute syntax (`onchange={...}`, `oninput={...}`,
  `onclick={...}`, `onsubmit={...}`) instead of the deprecated
  `on:event` directive form.

### Added

- `Caravela.Flow` — `:tag` start option. When set, every notification
  is delivered wrapped as `{:caravela_flow, tag, original_msg}`,
  letting a single listener driving many flows demultiplex without
  forwarder processes.

### Changed

- `Caravela.Live.Domain` / `Caravela.Live.Form` — when the `updater` /
  `on_event` / `visible` macros reject a value they can't arity-check
  at compile time, the error message now points the reader at the
  accepted shapes (`fn ... end` or `&Module.fun/N`) and the
  wrap-it-in-`fn` workaround for bound function variables.
- `Caravela.Gen.Migration` moduledoc now documents the `:timestamp`
  option for deterministic output (snapshot tests / demo pages).
  Behavior unchanged; only documentation.

## [0.5.0] — 2026-04-18

Phase 5 — dynamic Svelte forms with server-driven visibility and
async validation, plus the `Caravela.Flow` GenServer runtime for
composable async workflows.

### Added

- `Caravela.Live.Form` — DSL layered on `Caravela.Live.Domain` for
  form-visibility predicates (`visible/2`) and async field validators
  (`validate_async/3`). Each form-domain module exposes
  `__caravela_form__/0`, `__caravela_form_visibility__/1`,
  `__caravela_form_visible__/2`, and `__caravela_form_validate_async__/3`
  for introspection and runtime dispatch.
- `Caravela.Gen.SvelteForm` — generator that reads a form-domain
  module plus its owning `Caravela.Schema.Domain` and emits
  `<Entity>FormDynamic.svelte`. The component declares
  `field_visibility` / `async_errors` props, wraps guarded fields in
  `{#if field_visibility.*}`, and debounces async-validation
  `pushEvent` calls client-side.
- `Caravela.Flow` / `Caravela.Flow.DSL` — `use Caravela.Flow` plus
  `flow/3`, `sequence`, `repeat`, `wait`, `wait_until`, `debounce`,
  `set_state`, `run`, `parallel`, `race`, and `each` macros. Compiles
  to nested step-tree structs in `Caravela.Flow.Steps`.
- `Caravela.Flow.Runner` — GenServer interpreting step trees. Supports
  retry/backoff (linear + exponential), `wait_until` that unblocks on
  `signal/2`, `debounce` that resets on state change during the
  pause, parallel/race task orchestration, and per-item `each`
  iteration with `{:ok|:skip|:error, _}` returns.
- `Caravela.Flow.Supervisor` — optional DynamicSupervisor for flow
  runners. `Caravela.Flow.start/3` attaches runners when the
  supervisor is running, falls back to unsupervised `start_link`
  otherwise (useful in tests and tooling).
- Top-level API: `Caravela.Flow.start/3`, `Caravela.Flow.signal/2`,
  `Caravela.Flow.get_state/1`, `Caravela.Flow.stop/1,2`. Flows deliver
  `{:flow_state, _}`, `{:flow_done, _}`, and `{:flow_error, _}`
  messages to the `:notify` pid.
- `docs/flows.md` — new guide covering the flow DSL, primitives, the
  real-time loop through LiveView + LiveSvelte, and the scope
  boundary (no event sourcing).
- `docs/live_runtime.md` — extended with `Caravela.Live.Form` and
  `Caravela.Gen.SvelteForm` sections.

### Scope

- Flows are strictly ephemeral: in-memory state, no persistence, no
  event sourcing. Teams needing durable event streams should use
  [Commanded](https://github.com/commanded/commanded).

## [0.4.0] — 2026-04-17

Phase 4 — LiveView + typed Svelte component generation,
`Caravela.Live.*` runtime for composable state, and a docs restructure.

### Added

- `mix caravela.gen.live` — generates three LiveView modules per entity
  (index / show / form) plus matching typed Svelte components and a
  TypeScript interfaces file. LiveViews mount components via
  `<LiveSvelte.render>` and delegate CRUD to the generated context, so
  authorization, hooks, and multi-tenant scoping apply for free.
- `Caravela.Gen.LiveView` + `Caravela.Gen.Svelte` — EEx-backed
  generators that emit index/show/form templates. Both respect the
  `# --- CUSTOM ---` marker (TypeScript uses `// --- CUSTOM ---`,
  Svelte uses `<!-- --- CUSTOM --- -->`).
- `Caravela.Gen.LiveRoute` — prints a `live` router scope snippet with
  four routes per entity (`index`, `:new`, `:show`, `:edit`), analogous
  to `Caravela.Gen.RouterScope` for the JSON API.
- `--with-domain` flag on `mix caravela.gen.live` — also emits a
  `Caravela.Live.Domain` companion module per entity and regenerates
  `form.ex` from a Template-backed variant. Index and show stay plain.
  Useful as an onramp to the `Caravela.Live.*` runtime.
- `Caravela.Live.Updater` — composable assigns-transformer helpers:
  `run/2,3`, `compose/2`, `embed/2`, and the `~>` pipe operator.
- `Caravela.Live.Domain` — `use` macro with `state`, `updater`,
  `on_event`, and `on_info` DSL for server-side state machines.
  Compile-time checks enforce updater arity (`1` or `2`) and require
  string event names. The `use` block sets
  `@caravela_live_domain __MODULE__` so `apply_updater/2,3` resolves
  inside domain bodies without an explicit module argument.
- `Caravela.Live.Template` — `use Caravela.Live.Template, domain: Mod`
  binds a LiveView to a `Live.Domain` module, injecting `mount/3`,
  `handle_event/3`, `handle_info/2`, and `apply_updater/2,3`. Unknown
  events log a warning instead of crashing; all callbacks are
  `defoverridable`.
- Naming helpers: `live_module/3`, `live_file_path/3`,
  `svelte_component_name/2`, `svelte_component_ref/3`,
  `svelte_file_path/3`, `svelte_types_file_path/1` — all version-aware.
- Documentation split into topic guides under `docs/` (getting_started,
  dsl, generators, multi_tenancy, versioning, graphql, livesvelte,
  live_runtime, regeneration), wired into `mix docs` as ex_doc extras.
  README trimmed to a minimal entry point.
- GitHub Actions workflow (`docs.yml`) that deploys `mix docs` output to
  GitHub Pages on every push to `main`. HexDocs continues to publish on
  tag release.

### Changed

- **BC-preserving rename.** `Caravela.Live.Updater.apply/2,3` → `run/2,3`
  to avoid shadowing `Kernel.apply/2,3`. `apply/2,3` remains as an
  undocumented alias.
- Generated Svelte `BookShow.svelte` now renders fields with the same
  null-safe expression as the index, so a missing field prints `—`
  instead of `undefined`.
- Generated Svelte `BookIndex.svelte` now includes a "New book" button
  that dispatches `pushEvent('new', {})`; the matching `handle_event`
  navigates to the form route.

### Fixed

- `Caravela.Live.Domain` docstring previously showed an example that
  wouldn't compile: `apply_updater/2,3` was invoked inside `on_event`
  bodies but the macro required `@caravela_live_domain`, which was only
  set by `use Caravela.Live.Template`. Now set by
  `Caravela.Live.Domain` too.
- Removed an unused `dirty` local from the generated Svelte form.

## [0.3.0] — 2026-04-17

Phase 3 — multi-tenancy, API versioning, Absinthe/GraphQL generation.

### Added

- `use Caravela.Domain, multi_tenant: true` — opts into row-level
  multi-tenancy. `Caravela.Tenant` auto-injects a `:tenant_id`
  (`:binary_id`, `null: false`) field into every entity, and the
  generated context gains `scope_tenant/2` + `inject_tenant_id/2`
  helpers driven by `context.tenant.id`.
- Migrations in multi-tenant domains add the `tenant_id` column and
  composite `[:tenant_id, :<fk>]` indexes alongside each FK index, plus
  a standalone `[:tenant_id]` index on tables with no FKs.
- `version "v1"` DSL directive — all generated Elixir modules and file
  paths are namespaced under the version segment
  (`MyApp.Library.V1.Book`, `MyAppWeb.V1.BookController`,
  `lib/my_app/library/v1/book.ex`). The router snippet is emitted at
  `scope "/api/v1", MyAppWeb.V1`. Table names stay version-free so rows
  are shared across versions.
- Two new compile-time validations: invalid version format (must match
  `~r/^v\d+$/`) and manual `:tenant_id` declarations colliding with
  auto-injection.
- `Caravela.Gen.GraphQL` — renders Absinthe object types, query object,
  and mutation object (with typed input objects) for the domain. Every
  resolver delegates to the generated context, so authorization, hooks,
  and tenant scoping apply to GraphQL for free. Tenant-injected fields
  are hidden from both object and input types.
- `mix caravela.gen.graphql` task — checks for Absinthe at runtime and
  prints an actionable error if the optional dependencies are missing.
- Generated controllers read `conn.assigns[:tenant]` into the context
  when the domain is multi-tenant.

## [0.2.0] — 2026-04-17

Phase 2 — hooks, permissions, Phoenix context + JSON API generators.

### Added

- Hook DSL: `on_create/2`, `on_update/2`, `on_delete/2` on any entity.
  Hooks run between authorization and the final `Repo` call in the
  generated context. `on_delete` may return `{:error, reason}` to
  abort the delete.
- Permission DSL: `can_read/2`, `can_create/2`, `can_update/2`,
  `can_delete/2`. `can_read` is applied as an Ecto query filter;
  the other three return booleans and a `false` short-circuits the
  context function with `{:error, :unauthorized}`.
- Compiled domain modules expose `__caravela_hook__/4` and
  `__caravela_permission__` dispatch functions with safe fallbacks.
- Three new compile-time validations: hook / permission arity, unknown
  entity references, duplicate (action, entity) declarations.
- `Caravela.Gen.Context` — Phoenix context generator with CRUD
  functions per entity (`list_`, `get_`, `get_!`, `change_`,
  `create_`, `update_`, `delete_`).
- `Caravela.Gen.Controller` — JSON controller generator (REST actions,
  standard status codes, changeset → 422 translation).
- `Caravela.Gen.RouterScope` — prints the `scope "/api", MyAppWeb do …
  end` snippet to paste into the host app's router.
- `Caravela.Gen.Custom` — preserves user code below the
  `# --- CUSTOM ---` marker across regenerations. Schemas, contexts,
  and controllers all ship with the marker.
- Mix tasks: `caravela.gen.context`, `caravela.gen.api`, and the
  all-in-one `caravela.gen`.

## [0.1.0] — 2026-04-17

Initial public release. Phase 1 — DSL, compiler, and schema/migration
generators.

### Added
- `Caravela.Domain` DSL: `entity`, `field`, `relation`.
- `Caravela.Compiler` with six compile-time validations: unknown field
  types, numeric-constraint/type mismatches, duplicate entities,
  dangling relation targets, incompatible cardinality, circular
  required `belongs_to` chains.
- `Caravela.Gen.EctoSchema` — Ecto schema generator (with changeset,
  required/format/length/numeric validations).
- `Caravela.Gen.Migration` — Ecto migration generator, topologically
  sorted, with foreign-key indexes and appropriate `on_delete` rules
  derived from `required:`.
- `mix caravela.gen.schema MyApp.Domains.<Module>` task with
  `--dry-run` and `--force` options.
- `:binary_id` primary and foreign keys by default.

[Unreleased]: https://github.com/rsousacode/caravela/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/rsousacode/caravela/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rsousacode/caravela/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rsousacode/caravela/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rsousacode/caravela/releases/tag/v0.1.0
