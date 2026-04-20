# Generators and mix tasks

Caravela ships one mix task per generator, plus an all-in-one task for
the backend trio. All tasks accept `--dry-run` (print, don't write),
`--force` (overwrite without prompting), and `--output DIR` (write
under `DIR` instead of `File.cwd!()`).

| Task                          | What it generates                                              |
|-------------------------------|----------------------------------------------------------------|
| `mix caravela.gen`            | Schemas + migration + context + JSON controllers               |
| `mix caravela.gen.schema`     | Ecto schemas + one migration                                   |
| `mix caravela.gen.context`    | Phoenix context module                                         |
| `mix caravela.gen.api`        | JSON controllers + prints the router scope snippet             |
| `mix caravela.gen.graphql`    | Absinthe types + queries + mutations                           |
| `mix caravela.gen.live`       | LiveViews + REST controllers + typed Svelte components + tests |
| `mix caravela.gen.auth`       | Authentication stack for an `authenticatable` entity           |
| `mix caravela.mcp`            | Launch the MCP server ([see mcp.md](mcp.md))                   |
| `mix caravela.check`          | Unified validation oracle (format + compile + credo + tests)   |
| `mix caravela.info`           | Human-readable IR dump for a domain                            |
| `mix caravela.ir`             | JSON IR dump for a domain                                      |

All file paths use standard Phoenix conventions:

```
lib/my_app/library/book.ex                        # schema
lib/my_app/library.ex                             # context
lib/my_app_web/controllers/book_controller.ex     # :rest entity controller
lib/my_app_web/schema/library_types.ex            # GraphQL
lib/my_app_web/live/library/book_live/index.ex    # :live entity
assets/svelte/library/BookIndex.svelte            # Svelte (both modes)
assets/svelte/library/BookIndex.test.ts           # Vitest smoke test
assets/svelte/types/library.ts                    # TypeScript
test/my_app_web/live/library/book_live_test.exs   # :live ExUnit
test/my_app_web/controllers/book_controller_test.exs  # :rest ExUnit
priv/repo/migrations/<ts>_create_library_tables.exs
```

Versioned domains nest a `v<n>/` segment in module names and file
paths; see [versioning](versioning.md).

## Flags specific to `mix caravela.gen.live`

- `--frontend MODE` - override every entity's declared render mode
  (`live` or `rest`). Useful for previewing generator output for the
  other transport without touching the DSL. See
  [svelte frontend](livesvelte.md) for the per-entity declaration
  (`entity :x, frontend: :rest do …`).

- `--no-tests` - skip emitting the ExUnit + Vitest test skeletons.
  By default the generator writes one `<entity>_live_test.exs` per
  `:live` entity, one `<entity>_controller_test.exs` per `:rest`
  entity, and one `*.test.ts` colocated next to every Svelte file.
  See [testing](testing.md).

- `--with-domain` - in addition to the three per-entity LiveViews
  (`index`, `show`, `form`), also emit a `Caravela.Live.Domain`
  companion module (e.g. `MyAppWeb.Library.BookLive.FormDomain`) and
  generate `form.ex` from the Template-backed variant. Index and show
  stay plain. Useful as an onramp to the [Live runtime](live_runtime.md).
  Applies only to `:live` entities.

```bash
mix caravela.gen.live --with-domain MyApp.Domains.Library
# → lib/my_app_web/live/library/book_live/form.ex
#   lib/my_app_web/live/library/book_live/form_domain.ex

mix caravela.gen.live --no-tests --frontend rest MyApp.Domains.Library
```

## Optional dependencies

Caravela's own deps are minimal (`ecto_sql`, `jason`). These are only
required if you use the corresponding generator:

```elixir
# GraphQL (mix caravela.gen.graphql)
{:absinthe, "~> 1.7"},
{:absinthe_plug, "~> 1.5"},
{:dataloader, "~> 2.0"},

# Svelte frontend (mix caravela.gen.live - both :live and :rest modes)
{:caravela_svelte, "~> 0.1"},

# Phoenix (any generator targeting web code)
{:phoenix, "~> 1.7"},
{:phoenix_live_view, "~> 1.0"},
{:postgrex, "~> 0.18"}
```

The mix tasks check at runtime and print a useful warning if a dep is
missing.

## Router registration

Caravela does not edit `router.ex` automatically. Drop one line into
your router and the `Caravela.Router` macro expands to the full
route list at compile time, reading the domain's IR:

```elixir
defmodule MyAppWeb.Router do
  use Phoenix.Router
  use Caravela.Router
  import CaravelaSvelte.Router  # needed only when any entity is :rest

  scope "/", MyAppWeb.Library do
    pipe_through :browser
    caravela_routes MyApp.Domains.Library
  end
end
```

`caravela_routes/1` emits `live` routes for `:live` entities,
`caravela_rest` routes for `:rest` entities (with `realtime: true`
when declared), and keeps version segments in module aliases so
Phoenix's scope-alias resolution continues to match
`MyAppWeb.V1.Library.BookLive.Index` under `version "v1"` domains.

`caravela_routes/2` accepts a `:session` option forwarded to
`live_session/3`, letting a group of `:live` entities share an
`on_mount` hook.

The JSON-API generator (`mix caravela.gen.api`) still prints a paste-
snippet for `resources` under `:api`, since it targets JSON-only
endpoints that don't go through `caravela_svelte`:

```elixir
scope "/api", MyAppWeb do
  pipe_through :api
  resources "/books", BookController, except: [:new, :edit]
end
```

See the [regeneration](regeneration.md) page for the sha256 header,
per-function `CUSTOM` blocks, and tail-marker semantics that make
re-runs safe.

## Render functions are pure

Every `Caravela.Gen.*.render/1,2` function is a pure function of the
compiled domain module - it builds a `{path, source}` tuple (or a list
of them) in memory and never touches the filesystem or starts Mix. The
mix tasks are thin CLI wrappers around these calls.

That means you can invoke a generator anywhere you have the domain
module loaded: from a test, from a Phoenix controller that previews
generator output, from an IEx session. Nothing special about the mix
entry point.

```elixir
domain = MyApp.Domains.Library.__caravela_domain__()
{path, src} = Caravela.Gen.Context.render(domain)
# `src` is the file contents; `path` is where the mix task *would*
# write it. Up to you whether to write, diff, or render inline.
```

## Deterministic migration output

`Caravela.Gen.Migration.render/2` stamps the current UTC time into the
migration filename prefix by default, so two back-to-back runs produce
different paths. For snapshot tests or demo pages that show generator
output side-by-side with a committed baseline, pin the prefix:

```elixir
Caravela.Gen.Migration.render(domain, timestamp: "00000000000000")
# → {"priv/repo/migrations/00000000000000_create_library_tables.exs", ...}
```

All other generators are already deterministic.
