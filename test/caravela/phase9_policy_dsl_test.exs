defmodule Caravela.Phase9PolicyDslTest do
  use ExUnit.Case, async: true

  alias Caravela.Policy.{ActionGate, Entry, FieldRule}
  alias Caravela.Schema.Domain

  setup do
    {:ok, domain: MyApp.Domains.PolicyLibrary.__caravela_domain__()}
  end

  describe "policy block parsing" do
    test "book policy captures scope, field rules, and action gates", %{domain: domain} do
      assert %Entry{
               entity: :books,
               has_scope?: true,
               fields: fields,
               actions: actions
             } = Domain.policy_for(domain, :books)

      field_names = Enum.map(fields, & &1.field)
      assert :price in field_names
      assert :internal_notes in field_names
      assert :cost_basis in field_names
      assert :author_email in field_names

      # Arity 1 rules vs. arity 2 rules
      %FieldRule{arity: 1} = Enum.find(fields, &(&1.field == :price))
      %FieldRule{arity: 2} = Enum.find(fields, &(&1.field == :author_email))

      gate_actions = Enum.map(actions, & &1.action)
      assert :create in gate_actions
      assert :update in gate_actions
      assert :delete in gate_actions

      %ActionGate{arity: 1} = Enum.find(actions, &(&1.action == :create))
      %ActionGate{arity: 2} = Enum.find(actions, &(&1.action == :update))
    end

    test "author policy captures just the email field rule", %{domain: domain} do
      assert %Entry{entity: :authors, has_scope?: false, fields: [rule], actions: []} =
               Domain.policy_for(domain, :authors)

      assert rule.field == :email
    end
  end

  describe "runtime dispatch functions" do
    test "scope rule passes the admin query through unchanged, filters for viewers" do
      import Ecto.Query, only: [from: 2]

      admin = %{id: "a", role: :admin, author_id: "a"}
      viewer = %{id: "v", role: :viewer, author_id: nil}

      # A bare Ecto query on a source table — no schema module required.
      base = from(b in "library_books", select: b.id)

      # admin scope returns the query unchanged (identity)
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_scope__(:books, base, admin) == base

      # viewer scope adds a where clause — `wheres` grows by one.
      %Ecto.Query{wheres: wheres_after} =
        MyApp.Domains.PolicyLibrary.__caravela_policy_scope__(:books, base, viewer)

      assert length(wheres_after) == length(base.wheres) + 1
    end

    test "arity-1 field rule returns boolean for any actor" do
      admin = %{role: :admin}
      editor = %{role: :editor}
      viewer = %{role: :viewer}

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(:books, :price, admin) ==
               true

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :price,
               editor
             ) == true

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :price,
               viewer
             ) == false

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :internal_notes,
               viewer
             ) == false
    end

    test "arity-2 field rule returns :per_record without a record; evaluates with record" do
      admin = %{id: "a", role: :admin}
      author = %{id: "author_id_1", role: :viewer}
      stranger = %{id: "stranger", role: :viewer}
      record = %{author_id: "author_id_1"}

      # No record → :per_record sentinel
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :author_email,
               stranger
             ) == :per_record

      # With record: admin always sees
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :author_email,
               admin,
               record
             ) == true

      # Author of the record sees
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :author_email,
               author,
               record
             ) == true

      # Unrelated viewer does not
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :author_email,
               stranger,
               record
             ) == false
    end

    test "action gates authorize create / update / delete" do
      admin = %{id: "a", role: :admin}
      editor = %{id: "e", role: :editor, author_id: "e"}
      viewer = %{id: "v", role: :viewer, author_id: nil}

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(:books, :create, admin) == true
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(:books, :create, editor) == true
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(:books, :create, viewer) == false

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(:books, :delete, admin) == true
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(:books, :delete, editor) == false

      # Update is arity-2, needs the record
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(
               :books,
               :update,
               editor,
               %{author_id: "e"}
             ) == true

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(
               :books,
               :update,
               editor,
               %{author_id: "someone_else"}
             ) == false
    end

    test "fallbacks are applied for unpolicied entities / fields / actions" do
      # `:publishers` has no policy at all → all defaults.
      assert MyApp.Domains.Library.__caravela_policy_scope__(:publishers, :query, %{}) == :query

      assert MyApp.Domains.Library.__caravela_policy_field_visible__(:publishers, :name, %{}) ==
               true

      assert MyApp.Domains.Library.__caravela_policy_allow__(:publishers, :create, %{}) == true
    end
  end

  describe "compile-time validation" do
    test "rejects a policy on an unknown entity" do
      assert_raise CompileError, ~r/unknown entity/, fn ->
        defmodule BadEntity do
          use Caravela.Domain

          entity :books do
            field :title, :string, required: true
          end

          policy :ghosts do
            allow :create, fn _ -> true end
          end
        end
      end
    end

    test "rejects a field rule for an unknown field" do
      assert_raise CompileError, ~r/unknown field/, fn ->
        defmodule BadField do
          use Caravela.Domain

          entity :books do
            field :title, :string, required: true
          end

          policy :books do
            field :does_not_exist, visible: fn _ -> true end
          end
        end
      end
    end

    test "rejects duplicate policy blocks for the same entity" do
      assert_raise CompileError, ~r/duplicate policy/, fn ->
        defmodule DupPolicy do
          use Caravela.Domain

          entity :books do
            field :title, :string, required: true
          end

          policy :books do
            allow :create, fn _ -> true end
          end

          policy :books do
            allow :delete, fn _ -> true end
          end
        end
      end
    end

    test "rejects an unsupported directive inside a policy block" do
      assert_raise CompileError, ~r/unsupported directive/, fn ->
        defmodule WeirdPolicy do
          use Caravela.Domain

          entity :books do
            field :title, :string, required: true
          end

          policy :books do
            IO.puts("hi")
          end
        end
      end
    end

    test "rejects an allow action outside of :create / :update / :delete" do
      assert_raise CompileError, ~r/policy allow expects/, fn ->
        defmodule BadAction do
          use Caravela.Domain

          entity :books do
            field :title, :string, required: true
          end

          policy :books do
            allow :publish, fn _ -> true end
          end
        end
      end
    end
  end
end

