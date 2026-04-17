# Changelog

All notable changes to Caravela are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
