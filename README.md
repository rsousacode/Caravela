<p align="center">
  <img src="assets/logo.svg" alt="Caravela" width="180" height="180"/>
</p>

# Caravela

*Declare your domain. Sail with the generated code.*

A schema-driven, composable full-stack framework for Phoenix projects.
You describe a domain (entities, fields, relations, hooks, permissions)
as an Elixir DSL; Caravela generates Ecto schemas, migrations, Phoenix
contexts, JSON controllers, LiveViews, and typed Svelte components.

> **Status — Phase 2.** The DSL, compiler, schema + migration
> generators (Phase 1) plus hooks, permissions, context, and JSON API
> generators (Phase 2) are in place. LiveView, Svelte, and Flow
> orchestration land in later phases.

## Installation

Add `caravela` to your deps in `mix.exs`:

```elixir
def deps do
  [
    {:caravela, "~> 0.2.0"}
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

  # Hooks

  on_create :books, fn changeset, _context ->
    if Ecto.Changeset.get_field(changeset, :published) do
      Ecto.Changeset.validate_required(changeset, [:published_at])
    else
      changeset
    end
  end

  on_update :books, fn changeset, _context ->
    if Ecto.Changeset.get_change(changeset, :published) == true do
      Ecto.Changeset.put_change(changeset, :published_at, DateTime.utc_now())
    else
      changeset
    end
  end

  # Permissions

  can_create :books, fn context ->
    context.current_user.role in [:admin, :editor]
  end

  can_update :books, fn book, context ->
    context.current_user.role == :admin or
      book.author_id == context.current_user.author_id
  end

  can_delete :books, fn _book, context ->
    context.current_user.role == :admin
  end
end
```

### 2. Generate everything

```bash
mix caravela.gen MyApp.Domains.Library
# * created priv/repo/migrations/…_create_library_tables.exs
# * created lib/my_app/library/author.ex
# * created lib/my_app/library/book.ex
# * created lib/my_app/library/publisher.ex
# * created lib/my_app/library.ex                    (context)
# * created lib/my_app_web/controllers/author_controller.ex
# * created lib/my_app_web/controllers/book_controller.ex
# * created lib/my_app_web/controllers/publisher_controller.ex
#
# (and prints a router scope snippet to paste into router.ex)
```

Or target a single layer:

```bash
mix caravela.gen.schema  MyApp.Domains.Library   # schemas + migration only
mix caravela.gen.context MyApp.Domains.Library   # context only
mix caravela.gen.api     MyApp.Domains.Library   # controllers + router scope
```

Pass `--dry-run` to preview, or `--force` to overwrite without prompts.

### 3. Migrate and run

```bash
mix ecto.migrate
mix phx.server

curl -X POST localhost:4000/api/books \
  -H "content-type: application/json" \
  -d '{"title":"Test Title"}'
# → 201 Created on valid input, 403 if can_create denies,
#   422 if the changeset fails validation or the hook rejects it.
```

## DSL reference

### `entity :<name> do ... end`

Declares one entity (one table). The name is plural (`:books`); the
generator derives a singular module name (`Book`), a plural table name
(`library_books`), and a path (`lib/<app>/library/book.ex`).

### `field :<name>, <type>, opts`

| option                     | applies to        | effect                              |
|----------------------------|-------------------|-------------------------------------|
| `required`                 | any               | `null: false` + `validate_required` |
| `default`                  | any               | column default                      |
| `min`, `max`               | numeric           | `validate_number`                   |
| `min_length`, `max_length` | string-like       | `validate_length`                   |
| `format`                   | string-like       | `validate_format` (regex)           |
| `precision`, `scale`       | numeric           | decimal precision/scale             |

Recognised types: `:string`, `:text`, `:integer`, `:bigint`, `:float`,
`:decimal`, `:boolean`, `:date`, `:time`, `:naive_datetime`,
`:utc_datetime`, `:binary`, `:binary_id`, `:uuid`, `:map`, `:json`,
`:jsonb`.

### `relation :<from>, :<to>, type: <t>`

`t` is one of `:has_many`, `:has_one`, `:belongs_to`, `:many_to_many`.
Declare either side of a relationship — Caravela infers the other.

### Hooks: `on_create`, `on_update`, `on_delete`

Hooks run inside the generated context, between authorization and the
final `Repo` call:

```elixir
on_create :books, fn changeset, context -> ... end     # → changeset
on_update :books, fn changeset, context -> ... end     # → changeset
on_delete :authors, fn author, context -> ... end      # → :ok | {:error, reason}
```

`context` is whatever map you pass to the context function. In the
generated controllers it defaults to `%{current_user: …, conn: conn}`.

If a `{:error, reason}` is returned from `on_delete`, the delete is
aborted and the tuple propagates back to the caller.

### Permissions: `can_read`, `can_create`, `can_update`, `can_delete`

```elixir
can_read   :books, fn query, context -> query end        # → Ecto.Query
can_create :books, fn context -> true end                # → boolean
can_update :books, fn book, context -> true end          # → boolean
can_delete :books, fn _book, context -> true end         # → boolean
```

`can_read` is applied as a query filter before `Repo.all`/`Repo.get`,
so restricted users never see forbidden rows. The other three return
booleans; a `false` short-circuits the context function with
`{:error, :unauthorized}`.

To use query macros like `where` / `from` inside `can_read`, add
`import Ecto.Query` at the top of your domain module.

## Compile-time validations

Every rule raises a `CompileError` pointing at the offending line:

1. Unknown field types (`:widget` etc.)
2. Numeric constraints on non-numeric fields (and vice versa)
3. Duplicate entity names
4. Relations referencing undeclared entities
5. Incompatible cardinality (e.g. both sides `:has_many`)
6. Circular chains of required `belongs_to` (unsatisfiable inserts)
7. Hooks / permissions with the wrong function arity
8. Hooks / permissions referring to unknown entities
9. Duplicate hook / permission for the same (action, entity)

## Regeneration safety — the `# --- CUSTOM ---` marker

Every generated file (schemas, context, controllers) ends with:

```elixir
  # --- CUSTOM ---
  # Custom code below this line is preserved on regeneration.
end
```

Anything you write below that line is preserved verbatim the next time
you run `mix caravela.gen`. Migrations are always emitted as fresh
timestamped files — write bridging `ALTER TABLE` migrations yourself.

## Primary keys and ids

Every generated schema uses `:binary_id` (UUID) primary and foreign
keys. No enumeration attacks, no sequence exhaustion, Ecto-native.

## What's in Phase 1 + 2

**Phase 1** — `Caravela.Domain` DSL (`entity`, `field`, `relation`), the
compiler with six validations, Ecto-schema and migration generators,
`mix caravela.gen.schema`.

**Phase 2** — hook DSL (`on_create`, `on_update`, `on_delete`),
permission DSL (`can_read`, `can_create`, `can_update`, `can_delete`),
Phoenix context generator, JSON controller generator, router-scope
printer, regeneration-safe `# --- CUSTOM ---` marker,
`mix caravela.gen.context`, `mix caravela.gen.api`, and `mix caravela.gen`.

## Roadmap

Later phases add LiveView modules that mount Svelte components via
LiveSvelte, typed Svelte component generation, Absinthe/GraphQL schema
generation, and a GenServer-backed flow runtime for composable async
workflows.

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
