defmodule Caravela.Phase9PolicyGenTest do
  use ExUnit.Case, async: true

  import Caravela.ASTAssertions
  import Caravela.SvelteAssertions

  alias Caravela.Gen.{Context, LiveView, Svelte}

  setup do
    {:ok, domain: MyApp.Domains.PolicyLibrary.__caravela_domain__()}
  end

  describe "generated context" do
    setup %{domain: domain} do
      {_path, src} = Context.render(domain)
      {:ok, src: src}
    end

    test "list_* pipes through apply_scope + project_fields", %{src: src} do
      assert_calls(src, :apply_scope, [:books, :_])
      assert_calls(src, :project_fields, [:books, :_])
      assert_calls(src, :project_field, [:books, :_])
    end

    test "compute_field_access routes every field through the domain dispatch", %{src: src} do
      # Every public field on :books hits __caravela_policy_field_visible__/3.
      # The clause cascade on the domain module picks the right result
      # at runtime — arity-1 rules return a boolean, arity-2 rules
      # return :per_record, unruled fields fall through to the
      # per-entity / default_policy fallback.
      assert_def(src, :compute_field_access, 2)

      for field <- [:title, :price, :author_email, :internal_notes, :cost_basis] do
        assert_calls(src, :__caravela_policy_field_visible__, [:books, field, :_],
          module: PolicyLibrary
        )
      end
    end

    test "exposes a public field_access/2 function", %{src: src} do
      assert_def(src, :field_access, 2)
      assert_calls(src, :compute_field_access, [:_, :_])
    end

    test "policy_authorize blocks create/update/delete when gate returns false", %{src: src} do
      assert_calls(src, :policy_authorize, [:books, :create, :_])
      assert_calls(src, :policy_authorize, [:books, :update, :_, :_])
      assert_calls(src, :policy_authorize, [:books, :delete, :_, :_])

      # policy_authorize delegates into the domain module's dispatch
      # function — match by short name since the full module alias is
      # `MyApp.Domains.PolicyLibrary`.
      assert_calls(src, :__caravela_policy_allow__, [:_, :_, :_], module: PolicyLibrary)
    end

    test "domain-module dispatch honours arity-2 rule at runtime" do
      # Pure domain-module behaviour — no generated source needed.
      admin = %{id: "a", role: :admin}
      viewer = %{id: "v", role: :viewer}

      # arity-2 rule called at arity 3 → :per_record sentinel.
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :author_email,
               viewer
             ) == :per_record

      # arity-2 rule with the record → concrete boolean.
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :author_email,
               admin,
               %{author_id: "anything"}
             ) == true
    end
  end

  describe "generated Svelte components" do
    test "index gates policy-ruled columns with {#if field_access.<field>}", %{domain: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookIndex.svelte") end)

      # Ruled columns have BOTH the gate and the header cell.
      for ruled <- [:price, :internal_notes, :cost_basis] do
        assert_contains(src, "{#if field_access.#{ruled}}")
      end

      # `title` has no policy rule → rendered unconditionally.
      refute_contains(src, "{#if field_access.title}")
      assert_contains(src, "<th>Title</th>")
    end

    test "index accepts field_access in $props with the typed interface", %{domain: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookIndex.svelte") end)

      assert_all_contain(src, [
        # Imports now include the per-entity Actions type alongside
        # the field-access interface. The assertion tolerates the
        # multi-line import block the generator emits.
        "Book,",
        "BookFieldAccess,",
        "BookActions,",
        "LiveHandle",
        "field_access?: BookFieldAccess;",
        "actions?: BookActions;",
        # Default includes every public field set to `true` so the
        # component renders fully when mounted without LiveView wiring.
        "field_access = { title: true, isbn: true, published: true, price: true"
      ])
    end

    test "show gates fields on field_access", %{domain: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookShow.svelte") end)

      assert_contains(src, "{#if field_access.price}")
      assert_contains(src, "{#if field_access.internal_notes}")
      refute_contains(src, "{#if field_access.title}")
    end

    test "form gates input-level visibility", %{domain: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookForm.svelte") end)

      assert_contains(src, "{#if field_access.price}")
      assert_contains(src, "{#if field_access.internal_notes}")
      refute_contains(src, "{#if field_access.title}")
    end
  end

  describe "generated TypeScript types" do
    setup %{domain: domain} do
      {_path, src} = Svelte.render_types(domain)
      {:ok, src: src}
    end

    test "emits a *FieldAccess interface per entity", %{src: src} do
      assert_contains(src, "export interface BookFieldAccess {")
      assert_contains(src, "export interface AuthorFieldAccess {")
    end

    test "BookFieldAccess reflects arity-1 as boolean, arity-2 as 'per_record'", %{src: src} do
      assert_all_contain(src, [
        "price: boolean;",
        "internal_notes: boolean;",
        "cost_basis: boolean;",
        "author_email: 'per_record';",
        # Fields without a rule default to literal `true`.
        "title: true;"
      ])
    end
  end

  describe "generated LiveViews" do
    test "index mount computes field_access + passes it to LiveSvelte", %{domain: domain} do
      {_path, src} = LiveView.render_entity(domain, book_entity(domain), :index)

      assert_calls(src, :field_access, [:books, :_], module: PolicyLibrary)
      assert_contains(src, "field_access: @field_access")
    end

    test "form mount also assigns field_access", %{domain: domain} do
      {_path, src} = LiveView.render_entity(domain, book_entity(domain), :form)

      assert_calls(src, :field_access, [:books, :_], module: PolicyLibrary)
      assert_contains(src, "field_access: @field_access")
    end
  end

  defp book_entity(domain),
    do: Enum.find(domain.entities, &(&1.name == :books))
end
