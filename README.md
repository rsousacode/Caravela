<p align="center">
  <img src="assets/logo.svg" alt="Caravela" width="180" height="180"/>
</p>

# Caravela

*Declare your domain. Sail with the generated code.*

A schema-driven, composable full-stack framework for Phoenix projects.
You describe a domain (entities, fields, relations) as an Elixir DSL;
Caravela generates Ecto schemas, migrations, Phoenix contexts,
controllers, LiveViews, and typed Svelte components.

> **Status — Phase 1.** The DSL, the compiler, and the Ecto-schema +
> migration generators are in place. Contexts, LiveView, Svelte, and
> Flow orchestration land in later phases.

## Installation

Add `caravela` to your deps in `mix.exs`:

```elixir
def deps do
  [
    {:caravela, "~> 0.1.0"}
  ]
end
```

Phoenix and `ecto_sql` are assumed to already be present in the host
app; Caravela generates code against them.

## Quick start

### 1. Declare a domain

```elixir
# lib/my_app/domains/library.ex
defmodule MyApp.Domains.Library do
  use Caravela.Domain

  entity :authors do
    field :name, :string, required: true
    field :bio, :text
    field :born, :date
  end

  entity :books do
    field :title, :string, required: true, min_length: 3
    field :isbn, :string, format: ~r/^\d{13}$/
    field :published, :boolean, default: false
    field :price, :decimal, precision: 10, scale: 2
  end

  entity :publishers do
    field :name, :string, required: true
    field :country, :string
  end

  relation :authors, :books, type: :has_many
  relation :books, :publishers, type: :belongs_to
end
```

### 2. Generate schemas and a migration

```bash
mix caravela.gen.schema MyApp.Domains.Library
# * created priv/repo/migrations/20260417120000_create_library_tables.exs
# * created lib/my_app/library/author.ex
# * created lib/my_app/library/book.ex
# * created lib/my_app/library/publisher.ex
```

The generator drops files where a standard Phoenix app expects them.
Every file is plain Phoenix / Ecto code — no runtime magic.

Pass `--dry-run` to preview, or `--force` to overwrite existing files
without prompting.

### 3. Migrate

```bash
mix ecto.migrate
```

The generated migration creates tables in dependency order and adds
foreign-key indexes. Required fields get `null: false`; required
`belongs_to` relations become `on_delete: :delete_all` (non-required
become `:nilify_all`).

## DSL reference

### `entity :<name> do ... end`

Declares one entity (one table). The name is plural (`:books`); the
generator derives a singular module name (`Book`), a plural table name
(`library_books`), and a path (`lib/<app>/library/book.ex`).

### `field :<name>, <type>, opts`

| option        | applies to        | effect                        |
|---------------|-------------------|-------------------------------|
| `required`    | any               | `null: false` + `validate_required` |
| `default`     | any               | column default                |
| `min`, `max`  | numeric           | `validate_number`             |
| `min_length`, `max_length` | string-like | `validate_length` |
| `format`      | string-like       | `validate_format` (regex)     |
| `precision`, `scale` | numeric    | decimal precision/scale       |

Recognised types: `:string`, `:text`, `:integer`, `:bigint`, `:float`,
`:decimal`, `:boolean`, `:date`, `:time`, `:naive_datetime`,
`:utc_datetime`, `:binary`, `:binary_id`, `:uuid`, `:map`, `:json`,
`:jsonb`.

### `relation :<from>, :<to>, type: <t>`

`t` is one of `:has_many`, `:has_one`, `:belongs_to`, `:many_to_many`.
Declare either side of a relationship — Caravela infers the other.

## Compile-time validations

The DSL is validated before any code is generated. Each rule raises
a `CompileError` with a file/line pointing at the declaration:

1. Unknown field types (`:widget` etc.)
2. Numeric constraints on non-numeric fields (and vice versa)
3. Duplicate entity names
4. Relations referencing undeclared entities
5. Incompatible cardinality (e.g. both sides `:has_many`)
6. Circular chains of required `belongs_to` (unsatisfiable inserts)

## Primary keys and ids

Every generated schema uses `:binary_id` (UUID) primary and foreign
keys. No enumeration attacks, no sequence exhaustion, and Ecto-native.

## What's in Phase 1

- `Caravela.Domain` DSL: `entity`, `field`, `relation`
- `Caravela.Compiler` with six validations
- `Caravela.Gen.EctoSchema` — Ecto schema generator (with changeset)
- `Caravela.Gen.Migration` — Ecto migration generator (topologically
  sorted, FK indexes)
- `mix caravela.gen.schema MyApp.Domains.<Module>`

## Roadmap

Later phases add Phoenix contexts, JSON controllers, LiveView modules
that mount Svelte components via LiveSvelte, typed Svelte component
generation, Absinthe/GraphQL schema generation, and a GenServer-backed
flow runtime for composable async workflows.

## License

Caravela is licensed under the
[Mozilla Public License 2.0](LICENSE) (MPL-2.0). In short:

- You can use Caravela — including in closed-source Phoenix applications
  — freely.
- If you modify a Caravela source file and distribute it, that file must
  stay under MPL-2.0, with authorship and copyright notices intact.
- You may not strip attribution or pass this work off as your own.

See [NOTICE](NOTICE) for the full attribution and anti-plagiarism
statement.

## Supporting the project

Caravela is built in the open and free to use. If it saves you time or
ships something you're proud of, please consider sponsoring its
development — donation channels (GitHub Sponsors, Open Collective, etc.)
will be linked here once set up.

Every contribution, from a PR to a coffee, helps keep the sails full.
