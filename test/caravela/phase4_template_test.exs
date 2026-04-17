defmodule Caravela.Phase4TemplateTest do
  @moduledoc """
  Exercises `Caravela.Live.Template` using a minimal "socket" — a plain
  map with `:assigns` — so we don't need a running LiveView process.
  The generated mount/3 and handle_event/3 clauses only touch
  `socket.assigns` via the Updater helpers, which work on any map.
  """

  use ExUnit.Case, async: true

  defmodule CounterDomain do
    use Caravela.Live.Domain

    state do
      field :count, :integer, default: 0
      field :last_event, :string, default: nil
    end

    updater(:increment, fn %{count: n} = s -> %{s | count: n + 1} end)
    updater(:decrement, fn %{count: n} = s -> %{s | count: n - 1} end)
    updater(:set_count, fn s, n -> %{s | count: n} end)

    on_event("inc", fn socket ->
      %{
        socket
        | assigns:
            Map.merge(socket.assigns, %{count: socket.assigns.count + 1, last_event: "inc"})
      }
    end)

    on_event("set", fn socket, %{"n" => n} ->
      %{socket | assigns: Map.merge(socket.assigns, %{count: n, last_event: "set"})}
    end)
  end

  test "apply_updater/2 resolves a 1-arity updater and updates assigns" do
    socket = %{assigns: %{count: 0, last_event: nil}}

    fun = CounterDomain.__caravela_live_updater__(:increment)
    assert is_function(fun, 1)

    updated = Caravela.Live.Updater.run(socket, fun)
    assert updated.assigns.count == 1
  end

  test "apply_updater/3 resolves a 2-arity updater and threads the argument" do
    socket = %{assigns: %{count: 0, last_event: nil}}

    fun = CounterDomain.__caravela_live_updater__(:set_count)
    assert is_function(fun, 2)

    updated = Caravela.Live.Updater.run(socket, fun, 42)
    assert updated.assigns.count == 42
  end

  test "Template.__apply_updater__/3 raises for unknown names" do
    socket = %{assigns: %{}}

    assert_raise ArgumentError, ~r/no updater :nope defined/, fn ->
      Caravela.Live.Template.__apply_updater__(socket, :nope, CounterDomain)
    end
  end

  test "Template.__apply_updater__/3 with 1-arg updater refuses 2-arg name" do
    socket = %{assigns: %{count: 0, last_event: nil}}

    assert_raise ArgumentError, ~r/takes an argument/, fn ->
      Caravela.Live.Template.__apply_updater__(socket, :set_count, CounterDomain)
    end
  end

  test "events dispatched through the domain update the socket" do
    socket = %{assigns: %{count: 0, last_event: nil}}

    updated = CounterDomain.__caravela_live_event__("inc", socket, %{})
    assert updated.assigns.count == 1
    assert updated.assigns.last_event == "inc"
  end
end
