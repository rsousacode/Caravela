defmodule Caravela.Phase4DomainTest do
  use ExUnit.Case, async: true

  describe "Caravela.Live.Domain — state + updaters + on_event" do
    defmodule BookEditor do
      use Caravela.Live.Domain

      state do
        field :book, :map, default: %{}
        field :saving, :boolean, default: false
        field :flash, :string, default: nil
      end

      updater(:mark_saving, fn assigns -> %{assigns | saving: true} end)
      updater(:mark_saved, fn assigns -> %{assigns | saving: false, flash: "Saved"} end)
      updater(:set_book, fn assigns, book -> %{assigns | book: book} end)

      on_event("save", fn socket ->
        %{socket | assigns: Map.put(socket.assigns, :saved_seen, true)}
      end)

      on_event("validate", fn socket, %{"field" => f, "value" => v} ->
        %{socket | assigns: Map.put(socket.assigns, :last_change, {f, v})}
      end)
    end

    test "default state is exposed as a map" do
      assert BookEditor.__caravela_live_state__() == %{
               book: %{},
               saving: false,
               flash: nil
             }
    end

    test "state fields expose their declared types" do
      assert BookEditor.__caravela_live_state_fields__() == [
               {:book, :map},
               {:saving, :boolean},
               {:flash, :string}
             ]
    end

    test "updaters are looked up by name and return functions" do
      mark = BookEditor.__caravela_live_updater__(:mark_saving)
      assert is_function(mark, 1)
      assert mark.(%{saving: false}) == %{saving: true}
    end

    test "2-arity updaters accept an argument" do
      set = BookEditor.__caravela_live_updater__(:set_book)
      assert is_function(set, 2)
      assert set.(%{book: nil}, %{title: "Dune"}) == %{book: %{title: "Dune"}}
    end

    test "unknown updater returns nil" do
      assert BookEditor.__caravela_live_updater__(:nope) == nil
    end

    test "1-arity on_event handlers run with just the socket" do
      socket = %{assigns: %{}}
      updated = BookEditor.__caravela_live_event__("save", socket, %{})
      assert updated.assigns.saved_seen == true
    end

    test "2-arity on_event handlers receive params" do
      socket = %{assigns: %{}}

      updated =
        BookEditor.__caravela_live_event__("validate", socket, %{
          "field" => "title",
          "value" => "Foo"
        })

      assert updated.assigns.last_change == {"title", "Foo"}
    end

    test "unknown events return {:error, {:no_such_event, name}}" do
      socket = %{assigns: %{}}

      assert BookEditor.__caravela_live_event__("nope", socket, %{}) ==
               {:error, {:no_such_event, "nope"}}
    end
  end

  describe "on_info/2 and apply_updater inside domain bodies" do
    defmodule AsyncDomain do
      use Caravela.Live.Domain

      state do
        field :count, :integer, default: 0
        field :flash, :string, default: nil
      end

      updater :inc, fn %{count: n} = s -> %{s | count: n + 1} end
      updater :set_flash, fn s, msg -> %{s | flash: msg} end

      # Using `apply_updater` inside the body proves @caravela_live_domain
      # is set on the Domain module itself — the macro doesn't need the
      # LiveView's Template `use` to resolve the updater.
      on_event "bump", fn socket ->
        apply_updater(socket, :inc)
      end

      on_info({:flash, msg}, fn socket ->
        apply_updater(socket, :set_flash, msg)
      end)
    end

    test "apply_updater/2 resolves inside an on_event body" do
      socket = %{assigns: %{count: 0, flash: nil}}
      updated = AsyncDomain.__caravela_live_event__("bump", socket, %{})
      assert updated.assigns.count == 1
    end

    test "on_info dispatches by message pattern" do
      socket = %{assigns: %{count: 0, flash: nil}}
      updated = AsyncDomain.__caravela_live_info__({:flash, "hello"}, socket)
      assert updated.assigns.flash == "hello"
    end

    test "unknown messages return the socket unchanged (fallback)" do
      socket = %{assigns: %{count: 0, flash: nil}}
      assert AsyncDomain.__caravela_live_info__(:nope, socket) == socket
    end
  end

  describe "validations" do
    test "updater with wrong arity is rejected at compile time" do
      assert_raise ArgumentError, ~r/updater requires a function of arity/, fn ->
        defmodule BadUpdater do
          use Caravela.Live.Domain

          state do
            field :x, :integer, default: 0
          end

          updater(:bad, fn a, b, c -> {a, b, c} end)
        end
      end
    end

    test "on_event with non-binary name is rejected" do
      assert_raise ArgumentError, ~r/on_event name must be a string literal/, fn ->
        defmodule BadEvent do
          use Caravela.Live.Domain

          state do
          end

          on_event(:save, fn socket -> socket end)
        end
      end
    end
  end
end
