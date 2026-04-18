# Changelog

All notable changes to Caravela are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
