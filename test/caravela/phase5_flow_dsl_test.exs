defmodule Caravela.Phase5FlowDSLTest do
  use ExUnit.Case, async: true

  alias Caravela.Flow.Steps

  describe "DSL expands into step-tree structs" do
    defmodule DemoFlow do
      use Caravela.Flow

      flow :simple, initial_state: %{counter: 0} do
        set_state fn state -> %{state | counter: state.counter + 1} end
        wait 100
      end

      flow :loop, initial_state: %{n: 0} do
        repeat do
          wait_until fn state -> state.n > 0 end
          set_state fn state -> %{state | n: state.n - 1} end
        end
      end

      flow :retry_flow, initial_state: %{tries: 0} do
        run fn state ->
              {:ok, %{state | tries: state.tries + 1}}
            end, retries: 2, backoff: :exponential, base_delay: 50
      end

      flow :each_flow, initial_state: %{items: [1, 2, 3], sum: 0} do
        each :items, fn item, state ->
          {:ok, %{state | sum: state.sum + item}}
        end
      end
    end

    test "__caravela_flows__ lists declared names in declaration order" do
      assert DemoFlow.__caravela_flows__() == [:simple, :loop, :retry_flow, :each_flow]
    end

    test "__caravela_flow_initial_state__ returns the declared map" do
      assert DemoFlow.__caravela_flow_initial_state__(:simple) == %{counter: 0}
      assert DemoFlow.__caravela_flow_initial_state__(:loop) == %{n: 0}
    end

    test "unknown flow name returns nil from __caravela_flow__" do
      assert DemoFlow.__caravela_flow__(:nope) == nil
    end

    test "unknown flow name falls back to empty initial state" do
      assert DemoFlow.__caravela_flow_initial_state__(:nope) == %{}
    end

    test "a simple flow compiles to a Sequence of SetState + Wait" do
      tree = DemoFlow.__caravela_flow__(:simple)

      assert %Steps.Sequence{steps: [%Steps.SetState{}, %Steps.Wait{ms: 100}]} = tree
    end

    test "repeat wraps the body in a Repeat holding a Sequence" do
      tree = DemoFlow.__caravela_flow__(:loop)

      assert %Steps.Sequence{
               steps: [
                 %Steps.Repeat{
                   step: %Steps.Sequence{
                     steps: [%Steps.WaitUntil{}, %Steps.SetState{}]
                   }
                 }
               ]
             } = tree
    end

    test "run carries retry/backoff/base_delay from opts" do
      tree = DemoFlow.__caravela_flow__(:retry_flow)

      assert %Steps.Sequence{
               steps: [%Steps.Run{retries: 2, backoff: :exponential, base_delay: 50}]
             } = tree
    end

    test "each carries the key and fun" do
      tree = DemoFlow.__caravela_flow__(:each_flow)

      assert %Steps.Sequence{
               steps: [%Steps.Each{key: :items, fun: fun}]
             } = tree

      assert is_function(fun, 2)
    end
  end

  describe "validation" do
    test "flow with non-atom name is rejected at compile time" do
      assert_raise Caravela.DSLError, ~r/flow name must be an atom/, fn ->
        defmodule BadFlow do
          use Caravela.Flow

          flow("not-an-atom", do: set_state(fn s -> s end))
        end
      end
    end
  end
end
