# Changelog

All notable changes to Caravela are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
