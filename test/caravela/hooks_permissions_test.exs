defmodule Caravela.HooksPermissionsTest do
  use ExUnit.Case, async: true

  describe "domain IR carries hooks and permissions" do
    test "the Library fixture exposes hooks" do
      domain = MyApp.Domains.Library.__caravela_domain__()

      actions = Enum.map(domain.hooks, &{&1.action, &1.entity}) |> Enum.sort()

      assert actions == [
               {:on_create, :books},
               {:on_delete, :authors},
               {:on_update, :books}
             ]
    end

    test "the Library fixture exposes permissions" do
      domain = MyApp.Domains.Library.__caravela_domain__()

      actions = Enum.map(domain.permissions, &{&1.action, &1.entity}) |> Enum.sort()

      assert actions == [
               {:can_create, :books},
               {:can_delete, :books},
               {:can_read, :books},
               {:can_update, :books}
             ]
    end
  end

  describe "dispatch functions on the domain module" do
    test "__caravela_hook__/4 runs the declared function" do
      # on_delete :authors returns :ok by default; {:error, _} if context
      # carries has_published_books: true.
      assert :ok =
               MyApp.Domains.Library.__caravela_hook__(
                 :on_delete,
                 :authors,
                 %{id: "x"},
                 %{}
               )

      assert {:error, :has_published_books} =
               MyApp.Domains.Library.__caravela_hook__(
                 :on_delete,
                 :authors,
                 %{id: "x"},
                 %{has_published_books: true}
               )
    end

    test "__caravela_hook__ falls back when no hook is declared" do
      # No on_create hook for :authors — fallback returns changeset as-is.
      cs = %Ecto.Changeset{data: %{}, valid?: true}

      assert MyApp.Domains.Library.__caravela_hook__(:on_create, :authors, cs, %{}) == cs
    end

    test "__caravela_permission__ uses declared rules" do
      # can_create :books allows :admin and :editor only.
      assert MyApp.Domains.Library.__caravela_permission__(:can_create, :books, %{role: :admin}) ==
               true

      assert MyApp.Domains.Library.__caravela_permission__(:can_create, :books, %{role: :editor}) ==
               true

      assert MyApp.Domains.Library.__caravela_permission__(:can_create, :books, %{role: :viewer}) ==
               false
    end

    test "__caravela_permission__ falls back when no rule is declared" do
      # No can_create :authors — fallback returns true.
      assert MyApp.Domains.Library.__caravela_permission__(:can_create, :authors, %{}) == true

      # No can_update :publishers — fallback returns true.
      assert MyApp.Domains.Library.__caravela_permission__(
               :can_update,
               :publishers,
               %{},
               %{}
             ) == true
    end

    test "can_read falls back to the query unchanged" do
      # No can_read :authors — fallback returns the query arg as-is.
      assert MyApp.Domains.Library.__caravela_permission__(
               :can_read,
               :authors,
               :some_query,
               %{}
             ) == :some_query
    end
  end

  describe "validation failures" do
    test "hook on unknown entity is rejected" do
      assert_raise CompileError, ~r/hook on_create references unknown entity :ghosts/, fn ->
        defmodule BadHookEntity do
          use Caravela.Domain

          entity :authors do
            field :name, :string
          end

          on_create :ghosts, fn changeset, _ -> changeset end
        end
      end
    end

    test "permission on unknown entity is rejected" do
      assert_raise CompileError, ~r/permission can_read references unknown entity :ghosts/, fn ->
        defmodule BadPermEntity do
          use Caravela.Domain

          entity :authors do
            field :name, :string
          end

          can_read :ghosts, fn q, _ -> q end
        end
      end
    end

    test "hook with wrong arity is rejected" do
      assert_raise CompileError, ~r/on_create expects a function of arity 2, got arity 1/, fn ->
        defmodule BadHookArity do
          use Caravela.Domain

          entity :authors do
            field :name, :string
          end

          on_create :authors, fn cs -> cs end
        end
      end
    end

    test "permission with wrong arity is rejected" do
      assert_raise CompileError, ~r/can_create expects a function of arity 1, got arity 2/, fn ->
        defmodule BadPermArity do
          use Caravela.Domain

          entity :authors do
            field :name, :string
          end

          can_create :authors, fn _a, _b -> true end
        end
      end
    end

    test "duplicate hook for same (action, entity) is rejected" do
      assert_raise CompileError, ~r/duplicate hook on_create for entity :authors/, fn ->
        defmodule DupHook do
          use Caravela.Domain

          entity :authors do
            field :name, :string
          end

          on_create :authors, fn cs, _ -> cs end
          on_create :authors, fn cs, _ -> cs end
        end
      end
    end

    test "duplicate permission for same (action, entity) is rejected" do
      assert_raise CompileError, ~r/duplicate permission can_read for entity :authors/, fn ->
        defmodule DupPerm do
          use Caravela.Domain

          entity :authors do
            field :name, :string
          end

          can_read :authors, fn q, _ -> q end
          can_read :authors, fn q, _ -> q end
        end
      end
    end

    test "non-function argument is rejected" do
      assert_raise CompileError, ~r/on_create requires a function literal/, fn ->
        defmodule BadHookShape do
          use Caravela.Domain

          entity :authors do
            field :name, :string
          end

          on_create :authors, :not_a_fun
        end
      end
    end
  end

  describe "captured function references" do
    defmodule CaptureHost do
      def validate(cs, _ctx), do: cs
    end

    test "accepts a captured named function of the right arity" do
      defmodule CapturedOK do
        use Caravela.Domain

        entity :things do
          field :name, :string
        end

        on_create :things, &Caravela.HooksPermissionsTest.CaptureHost.validate/2
      end

      assert %Caravela.Schema.Domain{} = CapturedOK.__caravela_domain__()
    end

    test "rejects a captured named function of the wrong arity" do
      assert_raise CompileError, ~r/on_create expects a function of arity 2, got arity 1/, fn ->
        defmodule CapturedBad do
          use Caravela.Domain

          entity :things do
            field :name, :string
          end

          on_create :things, &is_atom/1
        end
      end
    end
  end
end
