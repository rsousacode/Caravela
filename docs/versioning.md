# API versioning

Declare a version at the top of the domain and Caravela threads it
through every generated artifact:

```elixir
defmodule MyApp.Domains.Library do
  use Caravela.Domain

  version "v1"

  entity :books do
    field :title, :string, required: true
  end
end
```

## What changes

| Layer         | Without version                          | With `version "v1"`                                 |
|---------------|------------------------------------------|-----------------------------------------------------|
| Schema module | `MyApp.Library.Book`                     | `MyApp.Library.V1.Book`                             |
| Schema file   | `lib/my_app/library/book.ex`             | `lib/my_app/library/v1/book.ex`                     |
| Context       | `MyApp.Library` (`lib/my_app/library.ex`) | `MyApp.Library.V1` (`lib/my_app/library/v1.ex`)     |
| Controller    | `MyAppWeb.BookController`                | `MyAppWeb.V1.BookController`                        |
| Controller file | `lib/my_app_web/controllers/book_controller.ex` | `lib/my_app_web/controllers/v1/book_controller.ex` |
| Router scope  | `scope "/api", MyAppWeb do`              | `scope "/api/v1", MyAppWeb.V1 do`                   |
| LiveView      | `MyAppWeb.Library.BookLive.Index`        | `MyAppWeb.V1.Library.BookLive.Index`                |
| LiveView file | `lib/my_app_web/live/library/book_live/index.ex` | `lib/my_app_web/live/v1/library/book_live/index.ex` |
| Svelte ref    | `library/BookIndex`                      | `v1/library/BookIndex`                              |
| GraphQL       | `MyAppWeb.Schema.LibraryTypes`           | `MyAppWeb.Schema.V1.LibraryTypes`                   |

## What doesn't change

**Table names.** `library_books` stays `library_books` across
versions. Different DSL versions share rows; renaming is a
column/type concern, not a table concern. If a later version changes a
column type, you write a bridging migration by hand (Caravela is
deliberately stateless about schema evolution — see
[regeneration](regeneration.md)).

## Multiple versions coexisting

To ship `v2` alongside `v1`, duplicate the domain file and bump the
string. `mix caravela.gen` will render a parallel tree under `v2/`
leaving `v1` untouched.

```elixir
# lib/my_app/domains/library_v1.ex
defmodule MyApp.Domains.LibraryV1 do
  use Caravela.Domain
  version "v1"
  # … unchanged …
end

# lib/my_app/domains/library_v2.ex
defmodule MyApp.Domains.LibraryV2 do
  use Caravela.Domain
  version "v2"
  # … new fields, new hooks …
end
```

Both versions generate into their own namespaces; your router has two
scopes (`/api/v1` and `/api/v2`); the database has one schema.

## Compile-time guard

Version strings must match `~r/^v\d+$/`. `"version-1"` or `"V1"` raise
a `CompileError` at compile time.
