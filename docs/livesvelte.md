# Svelte frontend (render modes)

`mix caravela.gen.live MyApp.Domains.Library` generates a working
Svelte frontend for every entity in the domain. Each entity picks one
of two render modes via its DSL declaration:

* `frontend: :live` (default) - Phoenix LiveView + WebSocket.
* `frontend: :rest` - Phoenix controller + Inertia-style HTTP.

Both modes mount Svelte components through
[`caravela_svelte`](https://hex.pm/packages/caravela_svelte), so the
same `BookIndex.svelte` works under either transport without
changes - the author barely notices which mode is in play.

## Setup

Add `caravela_svelte` to the consumer app:

```elixir
# mix.exs
{:caravela, "~> 0.13"},
{:caravela_svelte, "~> 0.1"}
```

Wire the client runtime into `assets/js/app.js` following the
[`caravela_svelte` docs](https://hexdocs.pm/caravela_svelte).

## Generated files

```
lib/my_app_web/live/library/book_live/{index,show,form}.ex   # :live mode
lib/my_app_web/controllers/book_controller.ex                # :rest mode
assets/svelte/library/{BookIndex,BookShow,BookForm}.svelte   # both modes
assets/svelte/library/{BookIndex,BookShow,BookForm}.test.ts  # Vitest smoke tests
assets/svelte/types/library.ts                               # shared TS
test/my_app_web/live/library/book_live_test.exs              # :live tests
test/my_app_web/controllers/book_controller_test.exs         # :rest tests
```

The trio of Svelte components is identical between modes. Mode is a
server-side decision; the Svelte component receives the same props
either way.

## Registering routes

Don't paste route snippets. `Caravela.Router` exposes a compile-time
macro that expands to the full route list based on each entity's
`frontend` / `realtime?` declaration:

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

`caravela_routes/1` expands into `live` routes for `:live` entities
and `caravela_rest` routes for `:rest` entities, with
`realtime: true` appended automatically when the entity opts in.
Versioned domains (`version "v1"`) insert the version segment into
the module aliases so Phoenix's scope alias resolution continues to
match the generated `MyAppWeb.V1.Library.BookLive.Index` layout.

```elixir
caravela_routes MyApp.Domains.Library,
  session: [on_mount: {MyAppWeb.Auth, :require_user}]
```

Passing `:session` wraps the `:live` routes in a `live_session/3`
block so a group of entities can share an `on_mount` hook.

## `:live` mode - what the generated LiveView looks like

```elixir
defmodule MyAppWeb.Library.BookLive.Index do
  use MyAppWeb, :live_view
  alias MyApp.Library

  def mount(_params, _session, socket) do
    context = build_context(socket)

    socket =
      socket
      |> assign(:context, context)
      |> assign(:field_access, Library.field_access(:books, context))
      |> assign(:actions, Library.action_access(:books, context))
      |> assign(:books, Library.list_books(context))
      |> assign(:loading, false)
      |> assign(:flash_message, nil)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <CaravelaSvelte.svelte
      name="library/BookIndex"
      props={%{
        books: @books,
        loading: @loading,
        flash_message: @flash_message,
        field_access: @field_access,
        actions: @actions
      }}
      socket={@socket}
    />
    """
  end
end
```

The LiveView is standard Phoenix - plain `mount/3`, explicit
`handle_event` clauses, the context module aliased at the top.
No Caravela runtime coupling in the default output.

## `:rest` mode - what the generated controller looks like

```elixir
defmodule MyAppWeb.BookController do
  use Phoenix.Controller, formats: [:html]

  alias MyApp.Library
  alias Caravela.ChangesetTranslator
  alias CaravelaSvelte.Caravela, as: CS

  def index(conn, _params) do
    context = build_context(conn)
    items = Library.list_books(context)
    field_access = field_access(context)
    actions = Library.action_access(:books, context)

    conn
    |> CS.put_field_access(field_access)
    |> CaravelaSvelte.render("library/BookIndex", %{
      books: items,
      field_access: field_access,
      actions: actions
    })
  end

  # … show / new / edit / create / update / delete …
end
```

`CaravelaSvelte.render/3` produces an Inertia-compatible HTTP
response (JSON for SPA navigation, full HTML on first load).
Structured changeset errors flow through `Caravela.ChangesetTranslator`
(see [validation](validation.md)).

## `realtime: true` for `:rest` entities

Declaring `realtime: true` on a `:rest` entity:

```elixir
entity :books, frontend: :rest, realtime: true do
  field :title, :string, required: true
end
```

… adds three things to the generated controller:

1. `CS.broadcast_patch/3` on create / update / delete, keyed by the
   conventional per-actor topic `"caravela:<entity>:actor:<id>"`.
2. JSON-Patch operations matching the list mutation (`add` /
   `replace` / `remove` on `/<plural>/<id>`).
3. A matching `caravela_rest "/books", BookController, realtime: true`
   line in the router expansion, which
   [`CaravelaSvelte.Router`](https://hexdocs.pm/caravela_svelte) wires
   into the SSE endpoint clients subscribe through.

`:live` entities already have LiveView's WebSocket for real-time, so
`realtime: true` on a `:live` entity is rejected at compile time with
a clear error.

## Version + multi-tenant flow-through

- Versioned domain → `MyAppWeb.V1.Library.BookLive.Index` under
  `lib/my_app_web/live/v1/…`, mounting `v1/library/BookIndex.svelte`.
  The Router macro inserts the `V1.` segment automatically.
- Multi-tenant domain → generated `build_context/1` picks up
  `socket.assigns[:tenant]` / `conn.assigns[:tenant]` automatically,
  so tenant scoping in the context Just Works.

## The `--with-domain` flag (`:live` mode only)

For an onramp to the more ambitious [Live runtime](live_runtime.md),
pass `--with-domain`:

```bash
mix caravela.gen.live --with-domain MyApp.Domains.Library
```

This emits one extra file per `:live` entity - a
`Caravela.Live.Domain`-backed companion module - and regenerates
`form.ex` to use `Caravela.Live.Template`. Index and show stay plain.
The Template-backed form is ~30% shorter and makes the Updater model
concrete. `:rest` entities are unaffected.

## Other flags

- `--frontend rest|live` - blanket override. Treats every entity in
  the domain as the given mode, ignoring DSL declarations. Useful
  for previewing generator output.
- `--no-tests` - skip emitting the ExUnit + Vitest test skeletons
  (they're emitted by default - see [testing](testing.md)).
- `--dry-run`, `--force`, `--output DIR` - standard across all
  generators.

## Client events (`:live` mode)

Svelte components receive `live` as a prop and call `live.pushEvent`
to dispatch events back. The generated components use these event
names:

| Component  | Event      | Params           | What the server does                   |
|------------|------------|------------------|----------------------------------------|
| Index      | `new`      | `{}`             | `push_navigate` to `/new`              |
| Index      | `edit`     | `{id}`           | `push_navigate` to `/<id>/edit`        |
| Index      | `delete`   | `{id}`           | `Library.delete_book/2` + refetch list |
| Show       | `edit`     | `{id}`           | `push_navigate` to `/<id>/edit`        |
| Show       | `back`     | `{}`             | `push_navigate` to index               |
| Form       | `validate` | `{field, value}` | Rebuild changeset, update `:errors`    |
| Form       | `save`     | `{}`             | `create_*` or `update_*`, navigate     |
| Form       | `cancel`   | `{}`             | `push_navigate` to index               |

Feel free to add your own - generated `handle_event` clauses live
above the `# --- CUSTOM ---` marker; anything you add below it
survives regeneration (see [regeneration](regeneration.md)).

## Client navigation (`:rest` mode)

`:rest` pages use Inertia-style SPA navigation through
`caravela_svelte`'s client helpers (`navigate`, `useForm`). See the
[`caravela_svelte` docs](https://hexdocs.pm/caravela_svelte) for the
full client API.

## Props your Svelte component sees

For `BookIndex.svelte`:

```ts
let {
  books = [],
  loading = false,
  flash_message = null,
  field_access = { title: true, isbn: true /* … */ },
  actions = { create: true, update: true, delete: true },
  live  // :live mode only; absent under :rest
}: {
  books?: Book[];
  loading?: boolean;
  flash_message?: string | null;
  field_access?: BookFieldAccess;
  actions?: BookActions;
  live?: LiveHandle;
} = $props();
```

For `BookForm.svelte`:

```ts
let {
  book = {},
  errors = {},
  saving = false,
  field_access = { /* … */ },
  actions = { create: true, update: true, delete: true },
  live
}: {
  book?: Partial<Book>;
  // Structured error shape from Caravela.ChangesetTranslator.
  // See docs/validation.md.
  errors?: Record<string, Array<{ code: string; params: object; message: string }>>;
  saving?: boolean;
  field_access?: BookFieldAccess;
  actions?: BookActions;
  live?: LiveHandle;
} = $props();
```

The TypeScript interfaces are regenerated from the domain IR. Changes
to `field :title, :string, required: true` in Elixir immediately flow
to `title: string` (no `?`) in TypeScript on the next `mix
caravela.gen.live`. See [policies](policies.md) for how
`BookFieldAccess` and `BookActions` relate to the `policy` block.

## SSR caveats

Both modes render components server-side via `caravela_svelte`'s Node
bridge by default. A few Svelte libraries load code lazily at runtime
in a way the Node bridge can't resolve:

- **Shiki** (syntax highlighter) - dynamically imports per-language
  grammar chunks. Under Node SSR the dynamic imports fail and the
  render crashes. Workaround: disable SSR in your app config:

  ```elixir
  # config/config.exs
  config :caravela_svelte, :ssr, false
  ```

  Client-side hydration still works; only the initial server render
  falls back to a blank placeholder until the Svelte runtime takes
  over.

If you hit a similar "works in the browser, crashes in SSR" pattern
with another library, the same switch applies.
