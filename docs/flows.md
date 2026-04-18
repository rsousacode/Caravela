# Flows — async workflow orchestration

`Caravela.Flow` is a small DSL + GenServer runtime for composable
async workflows: debouncing, retries, sagas, parallel tasks. It is
**deliberately scoped** to ephemeral orchestration — no event
sourcing, no CQRS, no read-model projections. Teams needing
append-only logs should reach for
[Commanded](https://github.com/commanded/commanded); flows deliberately
keep out of that territory so the CRUD half of Caravela stays clean.

Flows pair naturally with `Caravela.Live.*` + LiveSvelte: flow state
changes go out via a `:notify` pid, a LiveView re-assigns socket
state, LiveSvelte pushes the prop diff to the Svelte component, and
the UI reacts. No custom WebSocket code.

## The DSL

```elixir
defmodule MyApp.Flows.BookSyncFlow do
  use Caravela.Flow

  flow :sync_book, initial_state: %{dirty: false, book_id: nil} do
    repeat do
      wait_until fn state -> state.dirty end
      debounce 500

      sequence do
        set_state fn state -> %{state | dirty: :processing} end

        run fn state ->
          case MyApp.ExternalAPI.sync_book(state.book_id) do
            :ok                   -> {:ok, %{state | dirty: false}}
            {:error, :timeout}    -> {:retry, state}
            {:error, reason}      -> {:error, reason}
          end
        end, retries: 3, backoff: :exponential, base_delay: 200
      end
    end
  end

  flow :import_books, initial_state: %{urls: [], results: []} do
    sequence do
      parallel fn state ->
        Enum.map(state.urls, fn url ->
          fn -> MyApp.ExternalAPI.fetch_book(url) end
        end)
      end, collect_as: :fetched

      each :fetched, fn book_data, state ->
        case MyApp.Library.V1.create_book(book_data) do
          {:ok, book} -> {:ok, %{state | results: [book | state.results]}}
          {:error, reason} -> {:skip, reason}
        end
      end
    end
  end
end
```

Each `flow/3` block compiles into a step tree rooted at a `Sequence`.
Nested `repeat`/`sequence` blocks produce nested structs; every
step's fun is captured as-is and invoked at runtime.

## Step primitives

Every primitive maps onto a struct in `Caravela.Flow.Steps`. The
Ballerina equivalents are listed in the module doc and below.

| DSL                              | Struct         | Ballerina   | Description                                                   |
| -------------------------------- | -------------- | ----------- | ------------------------------------------------------------- |
| `sequence do ... end`            | `Sequence`     | `Co.Seq`    | Run inner steps in order                                      |
| `repeat do ... end`              | `Repeat`       | `Co.Repeat` | Loop the inner step forever                                   |
| `wait ms`                        | `Wait`         | `Co.Wait`   | Pause for a fixed duration                                    |
| `wait_until fun`                 | `WaitUntil`    | `Co.While`  | Block until `fun.(state)` is truthy; unblocks on `signal/2`   |
| `debounce ms`                    | `Debounce`     |             | Wait for `ms` of state-stability (resets on signal)           |
| `set_state fun`                  | `SetState`     | `Co.SetState` | Synchronously replace state                                 |
| `run fun, retries:, backoff:, base_delay:` | `Run`  | `Co.Await`  | Invoke async work with optional retry + backoff               |
| `parallel fun, collect_as:`      | `Parallel`     | `Co.All`    | Run a list of zero-arity funs concurrently, collect results   |
| `race tasks, collect_as:`        | `Race`         | `Co.Any`    | Run tasks concurrently, keep the first result                 |
| `each :key, fun`                 | `Each`         | `Co.For`    | Iterate a collection already in state                         |

`run/2` understands the following return shapes:

- `:ok` — advance, state unchanged
- `{:ok, new_state}` — advance with new state
- `{:retry, new_state}` — retry (decrements `retries`)
- `{:error, reason}` — retry; if `retries == 0`, fail the flow

`each/2` understands `{:ok, state}`, `{:skip, reason}`, and
`{:error, reason}`. `:skip` keeps iterating; `:error` aborts the
whole flow.

## Starting, signalling, reading state

```elixir
{:ok, pid} =
  Caravela.Flow.start(MyApp.Flows.BookSyncFlow, :sync_book,
    initial_state: %{dirty: false, book_id: "abc"},
    notify: self())

# Flip `dirty` to kick the sync from outside
Caravela.Flow.signal(pid, fn state -> %{state | dirty: true} end)

# Read current state at any time
Caravela.Flow.get_state(pid) #=> %{dirty: :processing, book_id: "abc"}

# Stop when you're done
Caravela.Flow.stop(pid)
```

The `:notify` pid receives three message shapes:

- `{:flow_state, new_state}` — whenever state changes
- `{:flow_done, final_state}` — when the flow completes normally
- `{:flow_error, reason}` — on `{:error, _}` from `run/each`

## Supervising flows

In production, start `Caravela.Flow.Supervisor` as part of your
application tree:

```elixir
children = [
  # ... Ecto Repo, Endpoint, PubSub, etc. ...
  Caravela.Flow.Supervisor
]

Supervisor.start_link(children, strategy: :one_for_one)
```

With the supervisor running, every `Caravela.Flow.start/3` call
attaches the new runner as a supervised child. Without it,
`start/3` falls back to an unsupervised `start_link` — handy in tests
and tooling.

## The real-time loop — Flow → LiveView → LiveSvelte → Svelte

```
Flow (GenServer)
  │ {:flow_state, %{dirty: :processing}}
  │ via `:notify`
  ▼
LiveView (handle_info)
  │ assign(socket, sync_status: state.dirty)
  │ LiveSvelte auto-pushes the prop change
  ▼
Svelte Component
  │ let { sync_status } = $props();
  │ const statusLabel = $derived(derive(sync_status));
  ▼
  Reactive DOM update — no manual WebSocket code.
```

### LiveView side

```elixir
defmodule MyAppWeb.Library.BookSyncLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, pid} =
      Caravela.Flow.start(MyApp.Flows.BookSyncFlow, :sync_book,
        initial_state: %{dirty: false, book_id: socket.assigns.book.id},
        notify: self())

    {:ok, assign(socket, flow_pid: pid, sync_status: :idle)}
  end

  def handle_info({:flow_state, state}, socket) do
    {:noreply, assign(socket, sync_status: state.dirty)}
  end

  def handle_info({:flow_done, _}, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <LiveSvelte.render name="library/BookSync" props={%{sync_status: @sync_status}} />
    """
  end
end
```

### Svelte side

```svelte
<script lang="ts">
  let { sync_status = "idle" }: { sync_status?: string | boolean } = $props();

  const statusLabel = $derived(
    sync_status === "idle"       ? "Ready" :
    sync_status === "processing" ? "Syncing…" :
    sync_status === false        ? "Synced ✓" : "Unknown"
  );
</script>

<div class="sync-indicator" class:syncing={sync_status === "processing"}>
  {statusLabel}
</div>
```

The Svelte component declares a prop and reacts — no `socket.on`,
no subscriptions, no ad-hoc WebSocket plumbing. LiveView + LiveSvelte
already own the transport; flows just feed it.

## Scope boundary (no event sourcing)

Flows are **ephemeral async orchestration** — live only while the
runner process is alive, state is in-memory only, and there is no
persistent log. If a runner crashes, the flow starts over from
initial state (or from the state you persisted externally). That's
the tradeoff for a tiny, predictable runtime.

If you need durable event streams, projections, or CQRS, use
[Commanded](https://github.com/commanded/commanded) — Caravela
intentionally does not compete with it.
