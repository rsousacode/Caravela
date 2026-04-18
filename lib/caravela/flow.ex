defmodule Caravela.Flow do
  @moduledoc """
  Top-level entry point for the ephemeral async-workflow system.

  `use Caravela.Flow` inside a module to declare flows via the DSL in
  `Caravela.Flow.DSL`:

      defmodule MyApp.Flows.BookSyncFlow do
        use Caravela.Flow

        flow :sync_book, initial_state: %{dirty: false, book_id: nil} do
          repeat do
            wait_until fn state -> state.dirty end
            debounce 500
            run fn state ->
              MyApp.ExternalAPI.sync_book(state.book_id)
            end, retries: 3, backoff: :exponential, base_delay: 200
          end
        end
      end

  Start a flow runner with `start/3`, send external updates with
  `signal/2`, and read the current state with `get_state/1`.

      {:ok, pid} =
        Caravela.Flow.start(MyApp.Flows.BookSyncFlow, :sync_book,
          initial_state: %{dirty: true, book_id: "abc"},
          notify: self())

      # Later, flip `dirty` to kick the sync
      Caravela.Flow.signal(pid, fn state -> %{state | dirty: true} end)

  While the flow runs, each state change is delivered to the `:notify`
  pid as `{:flow_state, new_state}`. A LiveView can forward these
  messages to assigns — LiveSvelte picks up the prop diff and the
  Svelte component re-renders reactively.

  > #### Scope {: .info}
  >
  > Flows are **ephemeral async orchestration** only: debouncing,
  > retries, sagas, parallel tasks. There is no event sourcing and no
  > CQRS. Applications needing append-only logs should use
  > [Commanded](https://github.com/commanded/commanded).
  """

  alias Caravela.Flow.{Runner, Supervisor}

  @doc false
  defmacro __using__(opts) do
    quote do
      use Caravela.Flow.DSL, unquote(opts)
    end
  end

  @doc """
  Start a flow runner.

      Caravela.Flow.start(MyApp.Flows.BookSyncFlow, :sync_book,
        initial_state: %{dirty: false, book_id: "abc"},
        notify: self())
      #=> {:ok, #PID<0.456.0>}

  Options:

    * `:initial_state` — overrides the flow's declared default state
    * `:notify` — a pid to receive `{:flow_state, ...}`,
      `{:flow_done, ...}`, `{:flow_error, ...}` messages

  If `Caravela.Flow.Supervisor` is running, the runner starts as a
  supervised child; otherwise it starts unsupervised (useful in tests).
  """
  def start(flow_module, flow_name, opts \\ [])
      when is_atom(flow_module) and is_atom(flow_name) do
    tree = flow_module.__caravela_flow__(flow_name)

    if is_nil(tree) do
      raise ArgumentError,
            "Caravela.Flow: no flow named #{inspect(flow_name)} on " <>
              "#{inspect(flow_module)}"
    end

    default_state = flow_module.__caravela_flow_initial_state__(flow_name)
    initial_state = Keyword.get(opts, :initial_state, default_state)
    notify = Keyword.get(opts, :notify)

    args = %{step_tree: tree, state: initial_state, notify: notify}

    case Process.whereis(Supervisor) do
      nil -> Runner.start_link(args)
      _pid -> Supervisor.start_runner(args)
    end
  end

  @doc """
  Apply a mutating function to a running flow's state. Unblocks
  `wait_until` and resets `debounce`.

      Caravela.Flow.signal(pid, fn state -> %{state | dirty: true} end)
  """
  defdelegate signal(pid, fun), to: Runner

  @doc "Read the flow's current state."
  defdelegate get_state(pid), to: Runner

  @doc "Stop a running flow."
  def stop(pid, reason \\ :normal), do: GenServer.stop(pid, reason)
end
