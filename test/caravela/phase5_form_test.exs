defmodule Caravela.Phase5FormTest do
  use ExUnit.Case, async: true

  describe "Caravela.Live.Form - visibility predicates + async validators" do
    defmodule BookForm do
      use Caravela.Live.Form,
        entity: MyApp.Library.Book,
        context_fields: [:current_user]

      state do
        field :attrs, :map, default: %{}
        field :current_user, :map, default: %{role: :guest}
      end

      visible :published_at, fn assigns ->
        Map.get(assigns.attrs, :published) == true
      end

      visible :price, fn assigns ->
        Map.get(assigns.current_user, :role) in [:admin, :editor]
      end

      validate_async :isbn, [debounce: 500], fn value, _assigns ->
        if is_binary(value) and String.length(value) == 13 do
          :ok
        else
          {:error, "must be 13 digits"}
        end
      end

      validate_async :title, fn value, _assigns ->
        if value in ["", nil], do: {:error, "required"}, else: :ok
      end
    end

    test "__caravela_form__ exposes entity, context_fields, and field lists" do
      meta = BookForm.__caravela_form__()

      assert meta.entity == MyApp.Library.Book
      assert meta.context_fields == [:current_user]
      assert meta.visible_fields == [:published_at, :price]
      assert meta.async_fields == [:isbn, :title]
    end

    test "debounces map carries the declared debounce for each async field" do
      meta = BookForm.__caravela_form__()

      assert meta.debounces == %{isbn: 500, title: 0}
    end

    test "field_visibility flips based on assigns" do
      hidden = %{attrs: %{}, current_user: %{role: :guest}}

      assert BookForm.__caravela_form_visibility__(hidden) == %{
               published_at: false,
               price: false
             }

      visible = %{attrs: %{published: true}, current_user: %{role: :admin}}

      assert BookForm.__caravela_form_visibility__(visible) == %{
               published_at: true,
               price: true
             }
    end

    test "undeclared fields default to visible" do
      assert BookForm.__caravela_form_visible__(:something_else, %{}) == true
    end

    test "async validators run and return :ok or {:error, reason}" do
      assigns = %{}

      assert BookForm.__caravela_form_validate_async__(:isbn, "1234567890123", assigns) == :ok

      assert BookForm.__caravela_form_validate_async__(:isbn, "short", assigns) ==
               {:error, "must be 13 digits"}
    end

    test "unknown async validator returns :ok (fallback)" do
      assert BookForm.__caravela_form_validate_async__(:unknown, "anything", %{}) == :ok
    end

    test "form-domain inherits Caravela.Live.Domain state + updater DSL" do
      # Because Caravela.Live.Form delegates to Caravela.Live.Domain, the
      # standard state/updater introspection is still available.
      assert BookForm.__caravela_live_state__() == %{
               attrs: %{},
               current_user: %{role: :guest}
             }
    end
  end

  describe "validations" do
    test "visible with non-atom field name is rejected at compile time" do
      assert_raise Caravela.DSLError, ~r/visible.*must be an atom/, fn ->
        defmodule BadVisible do
          use Caravela.Live.Form, entity: Foo

          state do
          end

          visible "not an atom", fn _ -> true end
        end
      end
    end

    test "validate_async with non-atom field name is rejected at compile time" do
      assert_raise Caravela.DSLError, ~r/validate_async.*must be an atom/, fn ->
        defmodule BadValidateAsync do
          use Caravela.Live.Form, entity: Foo

          state do
          end

          validate_async "nope", fn _v, _a -> :ok end
        end
      end
    end

    test "validate_async with negative debounce is rejected" do
      assert_raise Caravela.DSLError, ~r/non-negative integer/, fn ->
        defmodule BadDebounce do
          use Caravela.Live.Form, entity: Foo

          state do
          end

          validate_async :isbn, [debounce: -1], fn _v, _a -> :ok end
        end
      end
    end

    test "visible with wrong-arity fun is rejected" do
      assert_raise Caravela.DSLError, ~r/visible.*requires a function of arity/, fn ->
        defmodule BadVisibleArity do
          use Caravela.Live.Form, entity: Foo

          state do
          end

          visible :x, fn a, b -> {a, b} end
        end
      end
    end
  end
end
