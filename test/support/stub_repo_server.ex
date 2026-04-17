defmodule StubRepoServer do
  @moduledoc false
  # Minimal ETS-backed call recorder used by the generated-context
  # integration tests. Shared across modules that each build their own
  # stub Repo pointing at this recorder.

  use Agent

  def ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        # Start unlinked so we outlive any individual test's process.
        {:ok, _pid} = Agent.start(fn -> %{} end, name: __MODULE__)
        :ok

      _pid ->
        :ok
    end
  end

  def reset(mod) do
    ensure_started()
    Agent.update(__MODULE__, &Map.put(&1, mod, []))
  end

  def record_and_return(mod, call, return) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      Map.update(state, mod, [call], fn calls -> calls ++ [call] end)
    end)

    return
  end

  def calls(mod) do
    Agent.get(__MODULE__, &Map.get(&1, mod, []))
  end

  def last_call(mod) do
    case calls(mod) do
      [] -> nil
      list -> List.last(list)
    end
  end
end
