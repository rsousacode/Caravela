defmodule Caravela.HooksTest do
  use ExUnit.Case, async: true

  describe "domain IR carries hooks" do
    test "the Library fixture exposes hooks" do
      domain = MyApp.Domains.Library.__caravela_domain__()

      actions = Enum.map(domain.hooks, &{&1.action, &1.entity}) |> Enum.sort()

      assert actions == [
               {:on_create, :books},
               {:on_delete, :authors},
               {:on_update, :books}
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

        on_create :things, &Caravela.HooksTest.CaptureHost.validate/2
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
