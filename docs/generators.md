# Generators and mix tasks

Caravela ships one mix task per generator, plus an all-in-one task for
the backend trio. All tasks accept `--dry-run` (print, don't write),
`--force` (overwrite without prompting), and `--output DIR` (write
under `DIR` instead of `File.cwd!()`).

| Task                          | What it generates                                   |
|-------------------------------|-----------------------------------------------------|
| `mix caravela.gen`            | Schemas + migration + context + JSON controllers    |
| `mix caravela.gen.schema`     | Ecto schemas + one migration                        |
| `mix caravela.gen.context`    | Phoenix context module                              |
| `mix caravela.gen.api`        | JSON controllers + prints the router scope snippet  |
| `mix caravela.gen.graphql`    | Absinthe types + queries + mutations                |
| `mix caravela.gen.live`       | LiveViews + typed Svelte components + TS interfaces |

All file paths use standard Phoenix conventions:

```
lib/my_app/library/book.ex            # schema
lib/my_app/library.ex                 # context
lib/my_app_web/controllers/book_controller.ex
lib/my_app_web/schema/library_types.ex     (GraphQL)
lib/my_app_web/live/library/book_live/index.ex
assets/svelte/library/BookIndex.svelte     (LiveSvelte)
assets/svelte/types/library.ts             (TypeScript)
priv/repo/migrations/<ts>_create_library_tables.exs
```

Versioned domains nest a `v<n>/` segment in module names and file
paths; see [versioning](versioning.md).

## Flags specific to `mix caravela.gen.live`

- `--with-domain` — in addition to the three per-entity LiveViews
  (`index`, `show`, `form`), also emit a `Caravela.Live.Domain`
  companion module (e.g. `MyAppWeb.Library.BookLive.FormDomain`) and
  generate `form.ex` from the Template-backed variant. Index and show
  stay plain. Useful as an onramp to the [Live runtime](live_runtime.md).

```bash
mix caravela.gen.live --with-domain MyApp.Domains.Library
# → lib/my_app_web/live/library/book_live/form.ex
#   lib/my_app_web/live/library/book_live/form_domain.ex
```

## Optional dependencies

Caravela's own deps are minimal (`ecto_sql`, `jason`). These are only
required if you use the corresponding generator:

```elixir
# GraphQL (mix caravela.gen.graphql)
{:absinthe, "~> 1.7"},
{:absinthe_plug, "~> 1.5"},
{:dataloader, "~> 2.0"},

# LiveSvelte (mix caravela.gen.live)
{:live_svelte, "~> 0.19"},

# Phoenix (any generator targeting web code)
{:phoenix, "~> 1.7"},
{:phoenix_live_view, "~> 1.0"},
{:postgrex, "~> 0.18"}
```

The mix tasks check at runtime and print a useful error if a dep is
missing.

## Router snippets

Caravela does not edit `router.ex` automatically. Instead, each web
generator prints a `scope` block you paste in:

```elixir
# from mix caravela.gen.api
scope "/api", MyAppWeb do
  pipe_through :api
  resources "/books", BookController, except: [:new, :edit]
end

# from mix caravela.gen.live
scope "/library", MyAppWeb do
  pipe_through :browser
  live "/books", BookLive.Index, :index
  live "/books/new", BookLive.Form, :new
  live "/books/:id", BookLive.Show, :show
  live "/books/:id/edit", BookLive.Form, :edit
end
```

See the [regeneration](regeneration.md) page for the CUSTOM-marker
semantics that make re-runs safe.
