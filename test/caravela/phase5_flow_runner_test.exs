defmodule Caravela.Phase5FlowRunnerTest do
  @moduledoc """
  End-to-end tests for `Caravela.Flow.Runner`. Each test starts a real
  GenServer, drives it via `Caravela.Flow.signal/2`, and asserts on the
  `{:flow_state, _}` / `{:flow_done, _}` messages delivered to the
  caller via `notify: self()`.
  """

  use ExUnit.Case, async: true

  alias Caravela.Flow

  defmodule Flows do
    use Caravela.Flow

    flow :sequence_flow, initial_state: %{steps_done: []} do
      set_state fn s -> %{s | steps_done: [:a | s.steps_done]} end
      set_state fn s -> %{s | steps_done: [:b | s.steps_done]} end
      set_state fn s -> %{s | steps_done: [:c | s.steps_done]} end
    end

    flow :wait_until_flow, initial_state: %{ready: false, fired: false} do
      wait_until fn s -> s.ready end
      set_state fn s -> %{s | fired: true} end
    end

    flow :retry_flow, initial_state: %{attempts: 0} do
      run fn s ->
        new = %{s | attempts: s.attempts + 1}

        if new.attempts >= 3 do
          {:ok, new}
        else
          {:retry, new}
        end
      end, retries: 5, backoff: :linear, base_delay: 5
    end

    flow :error_flow, initial_state: %{} do
      run fn _ -> {:error, :boom} end
    end

    flow :error_with_retries_flow, initial_state: %{count: 0} do
      run fn s -> {:error, {:try, s.count + 1}} end, retries: 2, base_delay: 5
    end

    flow :debounce_flow, initial_state: %{value: 0, fired: false} do
      wait_until fn s -> s.value > 0 end
      debounce 40
      set_state fn s -> %{s | fired: true} end
    end

    flow :parallel_flow, initial_state: %{} do
      parallel fn _s -> [fn -> :a end, fn -> :b end, fn -> :c end] end,
        collect_as: :results
    end

    flow :each_flow, initial_state: %{numbers: [1, 2, 3], total: 0} do
      each :numbers, fn n, s ->
        {:ok, %{s | total: s.total + n}}
      end
    end

    flow :each_skip_flow, initial_state: %{numbers: [1, 2, 3, 4], total: 0} do
      each :numbers, fn n, s ->
        if rem(n, 2) == 0 do
          {:ok, %{s | total: s.total + n}}
        else
          {:skip, :odd}
        end
      end
    end
  end

  defp start!(name, opts \\ []) do
    opts = Keyword.put_new(opts, :notify, self())
    {:ok, pid} = Flow.start(Flows, name, opts)
    pid
  end

  test "sequence runs every step in order and finishes" do
    _pid = start!(:sequence_flow)

    assert_receive {:flow_state, %{steps_done: [:a]}}
    assert_receive {:flow_state, %{steps_done: [:b, :a]}}
    assert_receive {:flow_state, %{steps_done: [:c, :b, :a]}}
    assert_receive {:flow_done, %{steps_done: [:c, :b, :a]}}
  end

  test "wait_until blocks until signal unblocks it" do
    pid = start!(:wait_until_flow)

    refute_receive {:flow_state, %{fired: true}}, 50

    Flow.signal(pid, fn s -> %{s | ready: true} end)

    assert_receive {:flow_state, %{fired: true}}
    assert_receive {:flow_done, %{fired: true}}
  end

  test "run retries and eventually succeeds" do
    _pid = start!(:retry_flow)

    assert_receive {:flow_state, %{attempts: 1}}
    assert_receive {:flow_state, %{attempts: 2}}
    assert_receive {:flow_state, %{attempts: 3}}
    assert_receive {:flow_done, %{attempts: 3}}
  end

  test "run with no retries and an error terminates the flow" do
    Process.flag(:trap_exit, true)
    pid = start!(:error_flow)

    assert_receive {:flow_error, :boom}
    assert_receive {:EXIT, ^pid, {:shutdown, {:flow_error, :boom}}}
    refute Process.alive?(pid)
  end

  test "run exhausts retries then emits flow_error" do
    Process.flag(:trap_exit, true)
    pid = start!(:error_with_retries_flow)

    assert_receive {:flow_error, {:try, _}}
    assert_receive {:EXIT, ^pid, {:shutdown, {:flow_error, {:try, _}}}}
  end

  test "debounce waits for state stability before advancing" do
    pid = start!(:debounce_flow)

    # Flip `value` to 1 → wait_until unblocks, debounce(40) starts
    Flow.signal(pid, fn s -> %{s | value: 1} end)
    # Within the 40ms window, mutate state again → debounce resets
    Process.sleep(15)
    Flow.signal(pid, fn s -> %{s | value: 2} end)
    # fired should still be false because debounce hasn't completed
    refute_receive {:flow_state, %{fired: true}}, 10

    # Eventually, after stability, `fired` flips and flow finishes
    assert_receive {:flow_done, %{fired: true}}, 500
  end

  test "parallel collects all task results into collect_as key" do
    _pid = start!(:parallel_flow)

    assert_receive {:flow_done, %{results: results}}
    assert Enum.sort(results) == [:a, :b, :c]
  end

  test "each reduces a collection into state" do
    _pid = start!(:each_flow)

    assert_receive {:flow_done, %{total: 6}}
  end

  test "each with {:skip, _} continues without mutating state for that item" do
    _pid = start!(:each_skip_flow)

    assert_receive {:flow_done, %{total: 6}}
  end

  test "get_state returns the live flow state" do
    pid = start!(:wait_until_flow)

    # Blocked at wait_until → state should be the initial state
    assert Flow.get_state(pid) == %{ready: false, fired: false}
    Flow.stop(pid)
  end

  test "initial_state override wins over declared default" do
    _pid = start!(:wait_until_flow, initial_state: %{ready: true, fired: false})

    assert_receive {:flow_state, %{fired: true}}
    assert_receive {:flow_done, %{fired: true}}
  end
end
