# LiveSvelte frontend

`mix caravela.gen.live MyApp.Domains.Library` generates a working
frontend for every entity in the domain:

```
lib/my_app_web/live/library/book_live/{index,show,form}.ex
assets/svelte/library/{BookIndex,BookShow,BookForm}.svelte
assets/svelte/types/library.ts
```

Per entity you get a trio of Phoenix LiveViews — index (list + delete +
"new"), show (single record), form (create/edit with validate
round-trips) — each mounting a typed Svelte component via
[LiveSvelte](https://github.com/woutdp/live_svelte).
One TypeScript file per domain holds the entity interfaces, imported
by every component.

## Setup

Add LiveSvelte to the consumer app:

```elixir
# mix.exs
{:live_svelte, "~> 0.19"}
```

Then follow the LiveSvelte docs to wire it into `assets/js/app.js` and
`esbuild`/`vite`.

After generation, the mix task prints a router snippet for you to
paste:

```elixir
scope "/library", MyAppWeb do
  pipe_through :browser

  live "/books", BookLive.Index, :index
  live "/books/new", BookLive.Form, :new
  live "/books/:id", BookLive.Show, :show
  live "/books/:id/edit", BookLive.Form, :edit
end
```

## What the generated LiveViews look like

Each LiveView is standard Phoenix — plain `mount/3`, explicit
`handle_event` clauses, the context module aliased at the top. No
Caravela runtime coupling in the default output, which means you can
delete the `:caravela` dep and the LiveView still compiles and works.

```elixir
defmodule MyAppWeb.Library.BookLive.Index do
  use MyAppWeb, :live_view
  alias MyApp.Library

  def mount(_params, _session, socket) do
    context = build_context(socket)
    {:ok, assign(socket, books: Library.list_books(context), ...)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    # … delegate to Library.delete_book/2 …
  end

  def render(assigns) do
    ~H"""
    <LiveSvelte.render
      name="library/BookIndex"
      props={%{books: @books, loading: @loading, flash_message: @flash_message}}
    />
    """
  end
end
```

## Version + multi-tenant flow-through

- Versioned domain → `MyAppWeb.V1.Library.BookLive.Index` under
  `lib/my_app_web/live/v1/…`, mounting `v1/library/BookIndex.svelte`.
- Multi-tenant domain → generated `build_context/1` picks up
  `socket.assigns[:tenant]` automatically, so tenant scoping in the
  context Just Works.

## The `--with-domain` flag

For an onramp to the more ambitious [Live runtime](live_runtime.md),
pass `--with-domain`:

```bash
mix caravela.gen.live --with-domain MyApp.Domains.Library
```

This emits one extra file per entity — a
`Caravela.Live.Domain`-backed companion module — and regenerates
`form.ex` to use `Caravela.Live.Template`. Index and show stay plain.
The Template-backed form is ~30% shorter and makes the Updater model
concrete.

## Client events

Svelte components receive `pushEvent` as a prop and call it to send
events back. The generated components use these event names:

| Component  | Event      | Params                 | What the server does                    |
|------------|------------|------------------------|-----------------------------------------|
| Index      | `new`      | `{}`                   | `push_navigate` to `/new`               |
| Index      | `edit`     | `{id}`                 | `push_navigate` to `/<id>/edit`         |
| Index      | `delete`   | `{id}`                 | `Library.delete_book/2` + refetch list  |
| Show       | `edit`     | `{id}`                 | `push_navigate` to `/<id>/edit`         |
| Show       | `back`     | `{}`                   | `push_navigate` to index                |
| Form       | `validate` | `{field, value}`       | Rebuild changeset, update `:errors`     |
| Form       | `save`     | `{}`                   | `create_*` or `update_*`, navigate      |
| Form       | `cancel`   | `{}`                   | `push_navigate` to index                |

Feel free to add your own — generated `handle_event` clauses live
above the `# --- CUSTOM ---` marker; anything you add below it
survives regeneration (see [regeneration](regeneration.md)).

## Props your Svelte component sees

For `BookIndex.svelte`:

```ts
export let books: Book[] = [];
export let loading: boolean = false;
export let flash_message: string | null = null;
export let pushEvent: (event: string, payload: object) => void;
```

For `BookForm.svelte`:

```ts
export let book: Partial<Book> = {};
export let errors: Record<string, string[]> = {};
export let saving: boolean = false;
export let pushEvent: (event: string, payload: object) => void;
```

The TypeScript interfaces are regenerated from the domain IR — changes
to `field :title, :string, required: true` in Elixir immediately flow
to `title: string` (no `?`) in TypeScript on the next `mix caravela.gen.live`.

## Known incompatibilities with LiveSvelte SSR

LiveSvelte renders components server-side via Node by default. A few
Svelte libraries load code lazily at runtime in a way the Node SSR
bridge can't resolve:

- **Shiki** (syntax highlighter) — dynamically imports per-language
  grammar chunks. Under Node SSR the dynamic imports fail and the
  render crashes. Workaround: disable SSR in your app config:

  ```elixir
  # config/config.exs
  config :live_svelte, ssr: false
  ```

  Client-side hydration still works; only the initial server render
  falls back to a blank placeholder until the Svelte runtime takes
  over.

If you hit a similar "works in the browser, crashes in SSR" pattern
with another library, the same switch applies.
