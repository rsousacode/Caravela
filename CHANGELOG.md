# Changelog

All notable changes to Caravela are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — Phase 2

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

[Unreleased]: https://github.com/rsousacode/caravela/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rsousacode/caravela/releases/tag/v0.1.0
