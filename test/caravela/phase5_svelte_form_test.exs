defmodule Caravela.Phase5SvelteFormTest do
  use ExUnit.Case, async: true

  alias Caravela.Gen.SvelteForm

  defmodule BookFormDomain do
    use Caravela.Live.Form, entity: :books, context_fields: [:current_user]

    state do
      field :attrs, :map, default: %{}
    end

    visible :published, fn assigns ->
      Map.get(assigns.attrs, :advanced_mode) == true
    end

    visible :price, fn assigns ->
      Map.get(assigns.current_user || %{}, :role) in [:admin, :editor]
    end

    validate_async :isbn, [debounce: 500], fn _value, _assigns -> :ok end
  end

  setup do
    {:ok, domain: MyApp.Domains.Library.__caravela_domain__()}
  end

  describe "render/3 paths" do
    test "emits BookFormDynamic.svelte under the context directory", %{domain: domain} do
      {path, _src} = SvelteForm.render(BookFormDomain, domain)
      assert path == "assets/svelte/library/BookFormDynamic.svelte"
    end

    test "versioned domain places the file under the version segment" do
      domain = MyApp.Domains.TenantLibrary.__caravela_domain__()

      {path, _src} = SvelteForm.render(BookFormDomain, domain)

      assert path == "assets/svelte/v1/tenant_library/BookFormDynamic.svelte"
    end
  end

  describe "render/3 content" do
    setup %{domain: domain} do
      {_path, src} = SvelteForm.render(BookFormDomain, domain)
      {:ok, src: src}
    end

    test "imports the entity TypeScript interface", %{src: src} do
      assert src =~ "import type { Book } from '../types/library';"
    end

    test "declares field_visibility, async_errors, and pushEvent props", %{src: src} do
      assert src =~ "export let field_visibility: Record<string, boolean> = {};"
      assert src =~ "export let async_errors: Record<string, string | null> = {};"
      assert src =~ "export let pushEvent:"
    end

    test "declares a debounce timer for every async field", %{src: src} do
      assert src =~ "let isbnTimer: ReturnType<typeof setTimeout>;"
    end

    test "debounce delay is injected into the validate_async timeout", %{src: src} do
      assert src =~ ~s|pushEvent('validate_async', { field: 'isbn', value });|
      assert src =~ "}, 500);"
    end

    test "fields with visibility predicates are wrapped in {#if field_visibility.*}",
         %{src: src} do
      assert src =~ "{#if field_visibility.published}"
      assert src =~ "{#if field_visibility.price}"
    end

    test "fields without a predicate render unconditionally", %{src: src} do
      # `title` has no visibility predicate, so no `{#if field_visibility.title}`
      refute src =~ "{#if field_visibility.title}"
      # But the input still renders — match a fragment of its label/input
      assert src =~ "Title"
    end

    test "async-validated fields get an async-error block", %{src: src} do
      assert src =~ "{#if async_errors.isbn}"
    end

    test "emits the CUSTOM marker for regeneration", %{src: src} do
      assert src =~ "<!-- --- CUSTOM --- -->"
    end

    test "submit and cancel push the canonical events", %{src: src} do
      assert src =~ "pushEvent('save', {});"
      assert src =~ "pushEvent('cancel', {})"
    end
  end

  describe "dynamic_file_path/2" do
    test "without version", %{domain: domain} do
      assert SvelteForm.dynamic_file_path(domain, :books) ==
               "assets/svelte/library/BookFormDynamic.svelte"
    end

    test "with version" do
      domain = MyApp.Domains.TenantLibrary.__caravela_domain__()

      assert SvelteForm.dynamic_file_path(domain, :books) ==
               "assets/svelte/v1/tenant_library/BookFormDynamic.svelte"
    end
  end
end
