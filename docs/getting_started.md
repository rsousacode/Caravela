# Getting started

## Install

Add `caravela` to your deps in `mix.exs`:

```elixir
def deps do
  [
    {:caravela, "~> 0.5.0"}
  ]
end
```

Phoenix and `ecto_sql` are assumed to already be present in the host
app; Caravela generates code against them. If you plan to generate
GraphQL or LiveSvelte output, see [generators](generators.md) for the
additional optional deps.

## 1. Declare a domain

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

  can_create :books, fn context ->
    context.current_user.role in [:admin, :editor]
  end
end
```

See [the DSL reference](dsl.md) for every macro.

## 2. Generate the backend

```bash
mix caravela.gen MyApp.Domains.Library
# → Ecto schemas, a migration, a Phoenix context module, and JSON
#   controllers. A router snippet is printed for you to paste.
```

Or layer by layer:

```bash
mix caravela.gen.schema   MyApp.Domains.Library
mix caravela.gen.context  MyApp.Domains.Library
mix caravela.gen.api      MyApp.Domains.Library
mix caravela.gen.graphql  MyApp.Domains.Library
mix caravela.gen.live     MyApp.Domains.Library
```

All generators take `--dry-run` and `--force`. See
[generators](generators.md) for the full list.

## 3. Migrate and run

```bash
mix ecto.migrate
mix phx.server

curl -X POST localhost:4000/api/books \
  -H "content-type: application/json" \
  -d '{"title":"Test Title"}'
# → 201 Created on valid input, 403 if can_create denies,
#   422 if the changeset fails validation or the hook rejects it.
```

## Where to go next

- [DSL reference](dsl.md) — every macro, every field option, every compile-time validation.
- [Generators](generators.md) — the mix tasks and their flags.
- [Multi-tenancy](multi_tenancy.md) — row-level tenant scoping.
- [Versioning](versioning.md) — coexisting API versions from one source.
- [GraphQL](graphql.md) — Absinthe generation.
- [LiveSvelte frontend](livesvelte.md) — generated LiveView + Svelte components.
- [Live runtime](live_runtime.md) — opt-in composable state for hand-written LiveViews.
- [Regeneration](regeneration.md) — the `# --- CUSTOM ---` marker and safe re-runs.
