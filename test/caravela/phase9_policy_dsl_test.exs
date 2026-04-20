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

      # A bare Ecto query on a source table - no schema module required.
      base = from(b in "library_books", select: b.id)

      # admin scope returns the query unchanged (identity)
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_scope__(:books, base, admin) == base

      # viewer scope adds a where clause - `wheres` grows by one.
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

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(:books, :create, editor) ==
               true

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(:books, :create, viewer) ==
               false

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(:books, :delete, admin) == true

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(:books, :delete, editor) ==
               false

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

    test "permissive fallbacks for `default_policy: :allow` domains" do
      # `:publishers` has no policy at all. Library is declared with
      # `default_policy: :allow`, so the unpolicied fallback is
      # permissive: query pass-through, fields visible, actions allowed.
      assert MyApp.Domains.Library.__caravela_policy_scope__(:publishers, :query, %{}) == :query

      assert MyApp.Domains.Library.__caravela_policy_field_visible__(:publishers, :name, %{}) ==
               true

      assert MyApp.Domains.Library.__caravela_policy_allow__(:publishers, :create, %{}) == true
    end

    test "deny-by-default scopes unpolicied entities to zero rows" do
      import Ecto.Query, only: [from: 2]

      base = from(w in "policy_library_widgets", select: w.id)

      %Ecto.Query{wheres: wheres_after} =
        MyApp.Domains.PolicyLibrary.__caravela_policy_scope__(:widgets, base, %{role: :admin})

      assert length(wheres_after) == length(base.wheres) + 1
    end

    test "deny-by-default hides every field on an unpolicied entity" do
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :widgets,
               :name,
               %{role: :admin}
             ) == false

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :widgets,
               :name,
               %{role: :admin},
               %{}
             ) == false
    end

    test "deny-by-default denies every write on an unpolicied entity" do
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(
               :widgets,
               :create,
               %{role: :admin}
             ) == false

      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(
               :widgets,
               :delete,
               %{role: :admin},
               %{}
             ) == false
    end

    test "per-entity permissive fallback fires for entities with a policy block" do
      # `:authors` has a policy (only a field rule on :email) but no
      # `scope` or `allow` rules. Under deny-by-default the module-level
      # fallback would deny everything - but the per-entity permissive
      # fallback kicks in first, so list/create/update/delete on an
      # authenticated actor are allowed.
      import Ecto.Query, only: [from: 2]

      base = from(a in "policy_library_authors", select: a.id)

      # Scope is a pass-through (per-entity fallback), not a deny filter.
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_scope__(
               :authors,
               base,
               %{role: :viewer}
             ) == base

      # No allow rule declared → per-entity permissive fallback returns true.
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_allow__(
               :authors,
               :create,
               %{role: :viewer}
             ) == true

      # No field rule on :name → per-entity permissive fallback returns true.
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :authors,
               :name,
               %{role: :viewer}
             ) == true

      # But the declared rule on :email still wins - viewers can't see it.
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :authors,
               :email,
               %{role: :viewer}
             ) == false
    end

    test "rejects an invalid default_policy value at compile time" do
      assert_raise Caravela.DSLError, ~r/default_policy/, fn ->
        defmodule BadDefaultPolicy do
          use Caravela.Domain, default_policy: :maybe

          entity :things do
            field :name, :string
          end
        end
      end
    end
  end

  describe "compile-time validation" do
    test "rejects a policy on an unknown entity" do
      assert_raise Caravela.DSLError, ~r/unknown entity/, fn ->
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
      assert_raise Caravela.DSLError, ~r/unknown field/, fn ->
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

    test "multiple `policy` blocks for the same entity are additive" do
      # Additive blocks are a deliberate feature - lets you split
      # policy declarations across files / environments.
      defmodule AdditivePolicy do
        use Caravela.Domain

        entity :books do
          field :title, :string, required: true
        end

        policy :books do
          allow :create, fn _ -> true end
        end

        policy :books do
          allow :delete, fn _ -> false end
        end
      end

      domain = AdditivePolicy.__caravela_domain__()
      entry = Caravela.Schema.Domain.policy_for(domain, :books)
      actions = Enum.map(entry.actions, & &1.action) |> Enum.sort()
      assert actions == [:create, :delete]
    end

    test "duplicate `scope` / `field` / `allow` rules on the same entity are rejected" do
      # Silent clause-ordering resolution would be bewildering, so we
      # raise at compile time even when the rules are spread across
      # multiple additive policy blocks.
      assert_raise Caravela.DSLError, ~r/duplicate policy scope/, fn ->
        defmodule DupScope do
          use Caravela.Domain

          entity :books do
            field :title, :string
          end

          policy :books do
            scope fn q, _ -> q end
          end

          policy :books do
            scope fn q, _ -> q end
          end
        end
      end

      assert_raise Caravela.DSLError, ~r/duplicate policy field rule/, fn ->
        defmodule DupField do
          use Caravela.Domain

          entity :books do
            field :title, :string
          end

          policy :books do
            field :title, visible: fn _ -> true end
            field :title, visible: fn _ -> false end
          end
        end
      end

      assert_raise Caravela.DSLError, ~r/duplicate policy allow rule/, fn ->
        defmodule DupAllow do
          use Caravela.Domain

          entity :books do
            field :title, :string
          end

          policy :books do
            allow :create, fn _ -> true end
            allow :create, fn _ -> false end
          end
        end
      end
    end

    test "module-attribute reference as field opts raises a helpful error" do
      # AST dispatch can't see `@admin_opts` as a keyword list, so
      # instead of silently misrouting we raise a pointed error that
      # tells the user what shape to use.
      assert_raise Caravela.DSLError, ~r/literal keyword list with/, fn ->
        defmodule OptsRef do
          use Caravela.Domain

          @admin_opts [visible: fn _ -> true end]

          entity :books do
            field :title, :string
            field :price, :decimal
          end

          policy :books do
            field :price, @admin_opts
          end
        end
      end
    end

    test "arbitrary Elixir inside a policy block Just Works" do
      # The policy block is plain Elixir - `for`, `if`, `@module_attr`
      # expansions, helper calls all expand the same way they would
      # at module top-level. This test defines a module dynamically
      # and checks that the accumulated rules match what the source
      # would suggest after expansion.
      defmodule DynamicPolicy do
        use Caravela.Domain

        @admin_fields [:price, :cost_basis, :internal_notes]

        entity :books do
          field :title, :string, required: true
          field :price, :decimal
          field :cost_basis, :decimal
          field :internal_notes, :text
        end

        policy :books do
          scope fn q, _ -> q end

          for f <- @admin_fields do
            field f, visible: fn actor -> actor.role == :admin end
          end

          if Mix.env() == :test do
            allow :delete, fn _ -> true end
          end
        end
      end

      domain = DynamicPolicy.__caravela_domain__()
      entry = Caravela.Schema.Domain.policy_for(domain, :books)

      # All three admin fields iterated by `for` got rules attached.
      assert Enum.sort(Enum.map(entry.fields, & &1.field)) ==
               [:cost_basis, :internal_notes, :price]

      # The compile-time `if` branch ran, so :delete is gated.
      assert Enum.any?(entry.actions, &(&1.action == :delete))
    end

    test "rejects an allow action outside of :create / :update / :delete" do
      assert_raise Caravela.DSLError, ~r/policy allow expects/, fn ->
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
