defmodule Caravela.Phase4UpdaterTest do
  use ExUnit.Case, async: true

  alias Caravela.Live.Updater

  describe "compose/2" do
    test "applies a then b" do
      a = fn m -> Map.put(m, :a, 1) end
      b = fn m -> Map.put(m, :b, m.a + 1) end

      combined = Updater.compose(a, b)
      assert combined.(%{}) == %{a: 1, b: 2}
    end

    test "is associative" do
      a = fn m -> Map.update(m, :n, 1, &(&1 + 1)) end

      left = Updater.compose(Updater.compose(a, a), a)
      right = Updater.compose(a, Updater.compose(a, a))

      assert left.(%{}) == right.(%{})
      assert left.(%{}) == %{n: 3}
    end
  end

  describe "embed/2" do
    test "narrows an updater to a single key" do
      inc = fn %{n: n} = m -> %{m | n: n + 1} end

      scoped = Updater.embed(inc, :child)
      result = scoped.(%{child: %{n: 0}, sibling: :untouched})

      assert result == %{child: %{n: 1}, sibling: :untouched}
    end

    test "raises when the key is missing" do
      inc = fn m -> m end

      assert_raise KeyError, fn ->
        Updater.embed(inc, :missing).(%{other: 1})
      end
    end
  end

  describe "~> macro" do
    test "composes updaters left-to-right" do
      require Updater
      import Updater

      a = fn m -> Map.put(m, :step, [:a | Map.get(m, :step, [])]) end
      b = fn m -> Map.put(m, :step, [:b | Map.get(m, :step, [])]) end
      c = fn m -> Map.put(m, :step, [:c | Map.get(m, :step, [])]) end

      pipeline = a ~> b ~> c
      assert pipeline.(%{}).step == [:c, :b, :a]
    end
  end

  describe "run/2 and run/3" do
    test "run/2 updates socket.assigns via a 1-arity updater" do
      socket = %{assigns: %{n: 0}}
      inc = fn %{n: n} = m -> %{m | n: n + 1} end

      updated = Updater.run(socket, inc)
      assert updated.assigns.n == 1
    end

    test "run/3 threads the extra argument through a 2-arity updater" do
      socket = %{assigns: %{book: nil}}
      set = fn m, b -> %{m | book: b} end

      updated = Updater.run(socket, set, %{title: "Dune"})
      assert updated.assigns.book == %{title: "Dune"}
    end

    test "apply/2 and apply/3 remain as undocumented aliases" do
      socket = %{assigns: %{n: 0}}
      inc = fn %{n: n} = m -> %{m | n: n + 1} end

      assert Updater.apply(socket, inc).assigns.n == 1
      assert Updater.apply(socket, fn m, v -> %{m | n: v} end, 42).assigns.n == 42
    end
  end
end
