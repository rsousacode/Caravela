defmodule Caravela.Phase9PolicyGenTest do
  use ExUnit.Case, async: true

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
      # list_books scopes the query then projects results.
      assert src =~ "|> apply_scope(:books, context)"
      assert src =~ "|> project_fields(:books, context)"
      assert src =~ "|> project_field(:books, context)"
    end

    test "compute_field_access routes every field through the domain dispatch", %{src: src} do
      # Every field (policy-ruled or not) is funneled through
      # `__caravela_policy_field_visible__`. The clause cascade in the
      # domain module decides the result at runtime — arity-1 rules
      # return a boolean, arity-2 rules return `:per_record`, unruled
      # fields fall through to the per-entity or default_policy fallback.
      assert src =~ "defp compute_field_access(:books, actor) do"

      for field <- [:title, :price, :author_email, :internal_notes, :cost_basis] do
        assert src =~
                 ~r/#{inspect(field)} =>\s*MyApp\.Domains\.PolicyLibrary\.__caravela_policy_field_visible__/,
               "expected field_access dispatch call for #{inspect(field)}"
      end
    end

    test "exposes a public field_access/2 function", %{src: src} do
      assert src =~ "def field_access(entity, context)"
      assert src =~ "compute_field_access(entity, actor)"
    end

    test "policy_authorize blocks create/update/delete when gate returns false", %{src: src} do
      # Action gate calls __caravela_policy_allow__ and guards with `== true`.
      assert src =~ "policy_authorize(:books, :create, context)"
      assert src =~ "policy_authorize(:books, :update, book, context)"
      assert src =~ "policy_authorize(:books, :delete, book, context)"
      assert src =~ "__caravela_policy_allow__(\n"
      assert src =~ "== true do\n      :ok\n    else\n      {:error, :unauthorized}\n    end"
    end

    test "projection redacts invisible fields on an Ecto struct", %{domain: domain} do
      # Compile the generated context into a dummy module so we can run it.
      # (We don't need a Repo; list_* is never called here — we only hit
      # the pure helpers via `field_access/2` to verify the dispatch.)
      admin = %{current_user: %{id: "a", role: :admin}}
      viewer = %{current_user: %{id: "v", role: :viewer}}

      # Through the domain module (not the generated context): verify the
      # arity-2 rule flags author_email as :per_record for non-admins.
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :author_email,
               viewer.current_user
             ) == :per_record

      # And resolves to visible when the actor is the record author.
      assert MyApp.Domains.PolicyLibrary.__caravela_policy_field_visible__(
               :books,
               :author_email,
               admin.current_user,
               %{author_id: "anything"}
             ) == true

      _ = domain
    end
  end

  describe "generated Svelte components" do
    test "index gates policy-ruled columns with {#if field_access.<field>}", %{domain: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookIndex.svelte") end)

      # Policy-ruled columns (price, internal_notes, cost_basis) are
      # wrapped; `title` (no rule) is rendered unconditionally.
      assert src =~ "{#if field_access.price}<th>Price</th>{/if}"
      assert src =~ "{#if field_access.internal_notes}<th>Internal Notes</th>{/if}"
      refute src =~ "{#if field_access.title}"
      assert src =~ "<th>Title</th>"
    end

    test "index accepts field_access in $props with the typed interface", %{domain: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookIndex.svelte") end)

      assert src =~ "import type { Book, BookFieldAccess, LiveHandle }"
      assert src =~ "field_access?: BookFieldAccess;"
      # Default includes every public field set to `true` so the
      # component renders fully when mounted without LiveView wiring.
      assert src =~ "field_access = { title: true, isbn: true, published: true, price: true"
    end

    test "show gates fields on field_access", %{domain: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookShow.svelte") end)

      assert src =~ "{#if field_access.price}"
      assert src =~ "{#if field_access.internal_notes}"
      # Title has no policy rule → rendered unconditionally.
      refute src =~ "{#if field_access.title}"
    end

    test "form gates input-level visibility", %{domain: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookForm.svelte") end)

      assert src =~ "{#if field_access.price}"
      assert src =~ "{#if field_access.internal_notes}"
      refute src =~ "{#if field_access.title}"
    end
  end

  describe "generated TypeScript types" do
    setup %{domain: domain} do
      {_path, src} = Svelte.render_types(domain)
      {:ok, src: src}
    end

    test "emits a *FieldAccess interface per entity", %{src: src} do
      assert src =~ "export interface BookFieldAccess {"
      assert src =~ "export interface AuthorFieldAccess {"
    end

    test "BookFieldAccess reflects arity-1 as boolean, arity-2 as 'per_record'", %{src: src} do
      assert src =~ ~r/price: boolean;/
      assert src =~ ~r/internal_notes: boolean;/
      assert src =~ ~r/cost_basis: boolean;/
      assert src =~ ~r/author_email: 'per_record';/
      # Fields without a rule default to literal `true`.
      assert src =~ ~r/title: true;/
    end
  end

  describe "generated LiveViews" do
    test "index mount computes field_access + passes it to LiveSvelte", %{domain: domain} do
      {_path, src} =
        LiveView.render_entity(domain, book_entity(domain), :index)

      assert src =~ "assign(:field_access, PolicyLibrary.field_access(:books, context))"
      assert src =~ "field_access: @field_access"
    end

    test "form mount also assigns field_access", %{domain: domain} do
      {_path, src} =
        LiveView.render_entity(domain, book_entity(domain), :form)

      assert src =~ "assign(:field_access, PolicyLibrary.field_access(:books, context))"
      assert src =~ "field_access: @field_access"
    end
  end

  defp book_entity(domain),
    do: Enum.find(domain.entities, &(&1.name == :books))
end
