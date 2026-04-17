# Live runtime — `Caravela.Live.*`

The default `mix caravela.gen.live` output is intentionally vanilla
Phoenix — no Caravela imports, no macros, nothing to learn beyond
`handle_event`. That keeps CRUD pages easy to read, easy to patch by
hand, and easy to eject.

When you're **hand-writing** a complex stateful LiveView, that
plainness starts to cost. Editors with async validation, wizards with
branching steps, dashboards with a dozen event types — all benefit
from giving state transitions a name and composing them like
functions. That's what `Caravela.Live.*` is for.

Three modules, each small and independent:

- `Caravela.Live.Updater` — pure composition on assigns maps
- `Caravela.Live.Domain` — DSL to declare state + named updaters + event handlers
- `Caravela.Live.Template` — wiring for a LiveView that mounts a Domain module

You can use one without the others. `Updater` works in any LiveView
callback. `Domain` works without `Template` if you want to drive it
yourself. `Template` needs a `Domain`, but nothing else.

## When to reach for it

**Use `Caravela.Live.*`** when the LiveView has:

- More than ~5 event types
- Multiple sources of "loading" or "saving" state that need to clear together
- Async work (Task.async, PubSub subscribes) whose completion updates the UI
- Nested child state (a parent LiveView composing child-domain updaters with `embed/2`)

**Don't reach for it** when the LiveView is:

- A plain CRUD index/show/form (the generator's default output is already correct)
- One event type and less than a few lines of state
- Glue code with no meaningful state transitions

The generated CRUD output is the proof of the second case — four
events, six assigns, no domain needed.

## `Caravela.Live.Updater`

An updater is a pure function `(assigns -> assigns)` or
`(assigns, arg -> assigns)`. `Caravela.Live.Updater.run/2,3` applies
one to a socket, assigning the result. `compose/2` chains them;
`embed/2` narrows one to operate on a nested key; the `~>` macro is
sugar for `compose`.

```elixir
import Caravela.Live.Updater

mark_saving = fn s -> %{s | saving: true} end
clear_flash = fn s -> %{s | flash_message: nil} end

# horizontal composition
pipeline = mark_saving ~> clear_flash
socket = run(socket, pipeline)

# vertical composition — apply `increment` only to :child_state
scoped = embed(&ChildDomain.increment/1, :child_state)
socket = run(socket, scoped)
```

`Caravela.Live.Updater.apply/2,3` is an undocumented backwards-compat
alias for `run/2,3`. Prefer `run` — `apply` shadows `Kernel.apply/2,3`
and reads worse in pipelines.

## `Caravela.Live.Domain`

Declares a set of named state transitions as a DSL:

```elixir
defmodule MyApp.BookEditorDomain do
  use Caravela.Live.Domain

  state do
    field :book, :map, default: %{}
    field :saving, :boolean, default: false
    field :flash_message, :string, default: nil
  end

  updater :mark_saving, fn s -> %{s | saving: true} end
  updater :mark_saved,  fn s -> %{s | saving: false, flash_message: "Saved"} end
  updater :set_book,    fn s, book -> %{s | book: book} end

  # `apply_updater` resolves against this module — @caravela_live_domain
  # is set to __MODULE__ inside `use Caravela.Live.Domain`.
  on_event "save", fn socket ->
    apply_updater(socket, :mark_saving)
  end

  # Async responses handled symmetrically
  on_info {:saved, book}, fn socket ->
    socket
    |> apply_updater(:set_book, book)
    |> apply_updater(:mark_saved)
  end
end
```

The compiled module exposes four lookup functions consumed by
`Caravela.Live.Template`:

- `__caravela_live_state__/0` — the default assigns map
- `__caravela_live_updater__/1` — function lookup by name (or `nil`)
- `__caravela_live_event__/3` — dispatch an event name to its handler
- `__caravela_live_info__/2` — dispatch an async message pattern

At compile time the DSL rejects updaters with arities outside `[1, 2]`
and events with non-string names.

## `Caravela.Live.Template`

```elixir
defmodule MyAppWeb.BookEditorLive do
  use MyAppWeb, :live_view
  use Caravela.Live.Template, domain: MyApp.BookEditorDomain

  def render(assigns) do
    ~H"""
    <LiveSvelte.render
      name="library/BookEditor"
      props={%{book: @book, saving: @saving, flash_message: @flash_message}}
    />
    """
  end
end
```

The `use Template` macro injects:

- `mount/3` — assigns the domain's default state
- `handle_event/3` — dispatches to the domain's `on_event` handlers
- `handle_info/2` — dispatches to the domain's `on_info` handlers
- `apply_updater/2,3` — sugar for resolving updater names against the
  bound domain

Everything is `defoverridable`, so you can override any callback for
I/O-heavy logic while keeping the updater sugar.

Unknown events log a warning and leave the socket unchanged (rather
than crashing), so typos in Svelte `pushEvent` names are loud but
not fatal.

## Compose with `embed/2` for nested child domains

A parent LiveView that mounts several child domains can compose child
updaters without knowing their internals:

```elixir
import Caravela.Live.Updater

parent_updater =
  embed(&MyApp.EditorDomain.__caravela_live_updater__(:mark_saving).(&1), :editor) ~>
  embed(&MyApp.SidebarDomain.__caravela_live_updater__(:collapse).(&1), :sidebar)

Caravela.Live.Updater.run(socket, parent_updater)
```

## Onramp: `mix caravela.gen.live --with-domain`

Running the live generator with `--with-domain` emits a
`<Entity>Live.FormDomain` module next to each `form.ex`, and
regenerates `form.ex` to use `Caravela.Live.Template`. It's the
shortest path to a working example of the pattern without writing a
domain from scratch.
