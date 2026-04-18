defmodule Caravela.Flow.Runner do
  @moduledoc """
  GenServer that executes a flow step tree one step at a time.

  The runner holds a stack of pending steps plus the current flow
  state. On each `:advance` message it pops the top step, reduces it,
  and either pushes continuation steps, schedules a timed wake-up, or
  blocks waiting for an external `signal/2`.

  Notifications (`{:flow_state, state}`, `{:flow_done, state}`,
  `{:flow_error, reason}`) go to the `:notify` pid supplied at start
  time. Listeners typically use `handle_info/2` in a LiveView to
  re-assign socket state — LiveSvelte pushes the resulting prop diff
  to the Svelte component.
  """

  use GenServer

  alias Caravela.Flow.Steps

  # --- Client API -------------------------------------------------------

  @doc """
  Start a runner under the caller's supervision tree. `args` is a map
  containing at minimum `:step_tree`. Optional keys: `:state`,
  `:notify`.
  """
  def start_link(args) when is_map(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc false
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      restart: :transient,
      type: :worker
    }
  end

  @doc """
  Apply a state-mutating function to the running flow.

  Unblocks `WaitUntil`, resets `Debounce`, and broadcasts a
  `{:flow_state, new_state}` notification.
  """
  def signal(pid, fun) when is_function(fun, 1) do
    GenServer.cast(pid, {:signal, fun})
  end

  @doc "Synchronously read the flow's current state."
  def get_state(pid) do
    GenServer.call(pid, :get_flow_state)
  end

  # --- GenServer callbacks ---------------------------------------------

  @impl true
  def init(args) do
    step = Map.fetch!(args, :step_tree)
    flow_state = Map.get(args, :state, %{})
    notify = Map.get(args, :notify)

    state = %{
      stack: [step],
      flow_state: flow_state,
      notify: notify,
      mode: :running,
      debounce_snapshot: nil,
      debounce_ms: nil
    }

    send(self(), :advance)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_flow_state, _from, state) do
    {:reply, state.flow_state, state}
  end

  @impl true
  def handle_cast({:signal, fun}, state) do
    new_flow_state = fun.(state.flow_state)
    state = put_flow_state(state, new_flow_state)

    state =
      case state.mode do
        :blocked ->
          send(self(), :advance)
          %{state | mode: :running}

        :debouncing ->
          Process.send_after(self(), :debounce_check, state.debounce_ms)
          %{state | debounce_snapshot: new_flow_state}

        :running ->
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:advance, %{stack: []} = state) do
    notify(state, {:flow_done, state.flow_state})
    {:stop, :normal, state}
  end

  def handle_info(:advance, %{stack: [step | rest]} = state) do
    case execute(step, rest, state.flow_state) do
      {:continue, new_stack, new_flow_state} ->
        state = state |> put_flow_state(new_flow_state) |> Map.put(:stack, new_stack)
        send(self(), :advance)
        {:noreply, %{state | mode: :running}}

      {:wait, ms, new_stack, new_flow_state} ->
        state = state |> put_flow_state(new_flow_state) |> Map.put(:stack, new_stack)
        Process.send_after(self(), :advance, ms)
        {:noreply, %{state | mode: :running}}

      {:block, new_stack} ->
        {:noreply, %{state | stack: new_stack, mode: :blocked}}

      {:debounce, new_stack, ms} ->
        Process.send_after(self(), :debounce_check, ms)

        {:noreply,
         %{
           state
           | stack: new_stack,
             mode: :debouncing,
             debounce_snapshot: state.flow_state,
             debounce_ms: ms
         }}

      {:error, reason} ->
        notify(state, {:flow_error, reason})
        {:stop, {:shutdown, {:flow_error, reason}}, state}
    end
  end

  def handle_info(:debounce_check, %{mode: :debouncing} = state) do
    if state.flow_state == state.debounce_snapshot do
      send(self(), :advance)

      {:noreply, %{state | mode: :running, debounce_snapshot: nil, debounce_ms: nil}}
    else
      # A cast already rescheduled a fresh check with the new snapshot;
      # this old one is stale — drop it.
      {:noreply, state}
    end
  end

  def handle_info(:debounce_check, state), do: {:noreply, state}

  # --- Step execution --------------------------------------------------

  defp execute(%Steps.Sequence{steps: []}, rest, flow_state) do
    {:continue, rest, flow_state}
  end

  defp execute(%Steps.Sequence{steps: [first | more]}, rest, flow_state) do
    {:continue, [first, %Steps.Sequence{steps: more} | rest], flow_state}
  end

  defp execute(%Steps.Repeat{step: inner} = repeat, rest, flow_state) do
    # Push inner, then Repeat below so we loop forever after inner completes
    {:continue, [inner, repeat | rest], flow_state}
  end

  defp execute(%Steps.Wait{ms: ms}, rest, flow_state) do
    {:wait, ms, rest, flow_state}
  end

  defp execute(%Steps.WaitUntil{fun: fun} = step, rest, flow_state) do
    if fun.(flow_state) do
      {:continue, rest, flow_state}
    else
      {:block, [step | rest]}
    end
  end

  defp execute(%Steps.Debounce{ms: ms}, rest, _flow_state) do
    {:debounce, rest, ms}
  end

  defp execute(%Steps.SetState{fun: fun}, rest, flow_state) do
    {:continue, rest, fun.(flow_state)}
  end

  defp execute(
         %Steps.Run{fun: fun, retries: retries, backoff: backoff, base_delay: base_delay},
         rest,
         flow_state
       ) do
    case safe_call(fun, flow_state) do
      :ok ->
        {:continue, rest, flow_state}

      {:ok, new_state} ->
        {:continue, rest, new_state}

      {:error, reason} when retries <= 0 ->
        {:error, reason}

      {:error, _reason} ->
        schedule_retry(rest, flow_state, fun, retries, backoff, base_delay)

      {:retry, _new_state} when retries <= 0 ->
        {:error, :max_retries_exhausted}

      {:retry, new_state} ->
        schedule_retry(rest, new_state, fun, retries, backoff, base_delay)

      other ->
        {:error, {:invalid_run_return, other}}
    end
  end

  defp execute(
         %Steps.Parallel{tasks_fn: tasks_fn, collect_as: key, timeout: timeout},
         rest,
         flow_state
       ) do
    tasks = tasks_fn.(flow_state)

    results =
      tasks
      |> Enum.map(&Task.async/1)
      |> Enum.map(&Task.await(&1, timeout))

    {:continue, rest, Map.put(flow_state, key, results)}
  end

  defp execute(
         %Steps.Race{tasks: tasks, collect_as: key, timeout: timeout},
         rest,
         flow_state
       ) do
    case race_tasks(tasks, timeout) do
      {:ok, winner} -> {:continue, rest, Map.put(flow_state, key, winner)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute(%Steps.Each{key: key, fun: fun}, rest, flow_state) do
    items = Map.get(flow_state, key, [])

    case each_reduce(items, fun, flow_state) do
      {:ok, new_state} -> {:continue, rest, new_state}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute(other, _rest, _flow_state) do
    {:error, {:unknown_step, other}}
  end

  # --- Helpers ---------------------------------------------------------

  defp put_flow_state(state, new_flow_state) do
    if new_flow_state != state.flow_state do
      notify(state, {:flow_state, new_flow_state})
    end

    %{state | flow_state: new_flow_state}
  end

  defp notify(%{notify: nil}, _msg), do: :ok
  defp notify(%{notify: pid}, msg) when is_pid(pid), do: send(pid, msg)
  defp notify(_state, _msg), do: :ok

  defp safe_call(fun, arg) do
    fun.(arg)
  rescue
    e -> {:error, {:exception, e, __STACKTRACE__}}
  end

  defp schedule_retry(rest, flow_state, fun, retries, backoff, base_delay) do
    delay = base_delay
    next_base_delay = next_delay(backoff, base_delay)

    retry_step = %Steps.Run{
      fun: fun,
      retries: retries - 1,
      backoff: backoff,
      base_delay: next_base_delay
    }

    {:wait, delay, [retry_step | rest], flow_state}
  end

  defp next_delay(:linear, base), do: base
  defp next_delay(:exponential, base), do: base * 2
  defp next_delay(_, base), do: base

  defp race_tasks(tasks, timeout) do
    async_tasks = Enum.map(tasks, &Task.async/1)

    result =
      async_tasks
      |> Task.yield_many(timeout)
      |> Enum.find_value(fn
        {_task, {:ok, value}} -> {:ok, value}
        _ -> nil
      end)

    Enum.each(async_tasks, &Task.shutdown(&1, :brutal_kill))

    case result do
      nil -> {:error, :race_timeout}
      {:ok, _value} = ok -> ok
    end
  end

  defp each_reduce(items, fun, flow_state) do
    Enum.reduce_while(items, {:ok, flow_state}, fn item, {:ok, acc} ->
      case fun.(item, acc) do
        {:ok, new_acc} -> {:cont, {:ok, new_acc}}
        {:skip, _reason} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
