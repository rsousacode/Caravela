defmodule Caravela.Phase4GenTest do
  use ExUnit.Case, async: false

  alias Caravela.Gen.{LiveView, Svelte}
  alias Caravela.Naming

  setup do
    {:ok,
     plain: MyApp.Domains.Library.__caravela_domain__(),
     tenant: MyApp.Domains.TenantLibrary.__caravela_domain__()}
  end

  describe "Naming helpers — LiveView + Svelte" do
    test "live_module is <Web>.<Context>.<Entity>Live.<Kind> without version", %{plain: domain} do
      assert Naming.live_module(domain, :books, :index) ==
               MyAppWeb.Library.BookLive.Index

      assert Naming.live_module(domain, :books, :show) == MyAppWeb.Library.BookLive.Show
      assert Naming.live_module(domain, :books, :form) == MyAppWeb.Library.BookLive.Form
    end

    test "live_module inserts V1 segment when versioned", %{tenant: domain} do
      assert Naming.live_module(domain, :books, :index) ==
               MyAppWeb.V1.TenantLibrary.BookLive.Index
    end

    test "live_file_path follows the Phoenix live/ directory convention", %{plain: domain} do
      assert Naming.live_file_path(domain, :books, :index) ==
               "lib/my_app_web/live/library/book_live/index.ex"
    end

    test "live_file_path nests version under live/", %{tenant: domain} do
      assert Naming.live_file_path(domain, :books, :index) ==
               "lib/my_app_web/live/v1/tenant_library/book_live/index.ex"
    end

    test "svelte_component_name is CamelCase entity + kind" do
      assert Naming.svelte_component_name(:books, :index) == "BookIndex"
      assert Naming.svelte_component_name(:books, :show) == "BookShow"
      assert Naming.svelte_component_name(:books, :form) == "BookForm"
    end

    test "svelte_component_ref is the LiveSvelte path string", %{plain: plain, tenant: tenant} do
      assert Naming.svelte_component_ref(plain, :books, :index) == "library/BookIndex"
      assert Naming.svelte_component_ref(tenant, :books, :index) == "v1/tenant_library/BookIndex"
    end

    test "svelte_file_path lives under assets/svelte/", %{plain: plain, tenant: tenant} do
      assert Naming.svelte_file_path(plain, :books, :index) ==
               "assets/svelte/library/BookIndex.svelte"

      assert Naming.svelte_file_path(tenant, :books, :form) ==
               "assets/svelte/v1/tenant_library/BookForm.svelte"
    end

    test "svelte_types_file_path is one file per domain", %{plain: plain, tenant: tenant} do
      assert Naming.svelte_types_file_path(plain) == "assets/svelte/types/library.ts"
      assert Naming.svelte_types_file_path(tenant) == "assets/svelte/v1/types/tenant_library.ts"
    end
  end

  describe "Caravela.Gen.LiveView" do
    test "emits three LiveViews per entity", %{plain: domain} do
      files = LiveView.render_all(domain)
      paths = Enum.map(files, &elem(&1, 0))

      # 3 entities × 3 kinds = 9 files
      assert length(files) == 9

      for {entity, kind} <- [
            {"book_live", "index"},
            {"author_live", "show"},
            {"publisher_live", "form"}
          ] do
        assert Enum.any?(paths, &String.ends_with?(&1, "#{entity}/#{kind}.ex")),
               "missing #{entity}/#{kind}.ex in paths: #{inspect(paths)}"
      end
    end

    test "index LiveView calls the context list/delete and renders LiveSvelte", %{plain: domain} do
      {_path, src} =
        LiveView.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/index.ex") end)

      assert src =~ "use MyAppWeb, :live_view"
      assert src =~ "alias MyApp.Library"
      assert src =~ "Library.list_books(context)"
      assert src =~ "Library.delete_book(entity, context)"
      assert src =~ ~s|name="library/BookIndex"|
      assert src =~ "LiveSvelte.render"
    end

    test "index LiveView navigates to /new on the `new` event", %{plain: domain} do
      {_path, src} =
        LiveView.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/index.ex") end)

      assert src =~ ~s|handle_event("new"|
      assert src =~ ~s|push_navigate(socket, to: "/library/books/new")|
    end

    test "form LiveView handles both create and update flows", %{plain: domain} do
      {_path, src} =
        LiveView.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/form.ex") end)

      assert src =~ "Library.change_book"
      assert src =~ "Library.create_book(attrs, context)"
      assert src =~ "Library.update_book(entity, attrs, context)"
      assert src =~ "alias MyApp.Library.Book"
      assert src =~ "handle_event(\"validate\""
      assert src =~ "handle_event(\"save\""
      assert src =~ "handle_event(\"cancel\""
    end

    test "multi-tenant LiveViews read conn.assigns[:tenant]", %{tenant: domain} do
      {_path, src} =
        LiveView.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/index.ex") end)

      assert src =~ "tenant: socket.assigns[:tenant]"
    end

    test "versioned LiveView module + file path", %{tenant: domain} do
      {path, src} =
        LiveView.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/index.ex") end)

      assert path == "lib/my_app_web/live/v1/tenant_library/book_live/index.ex"
      assert src =~ "defmodule MyAppWeb.V1.TenantLibrary.BookLive.Index do"
      assert src =~ "alias MyApp.TenantLibrary.V1"
      assert src =~ ~s|name="v1/tenant_library/BookIndex"|
    end

    test "every generated LiveView is valid Elixir", %{plain: plain, tenant: tenant} do
      for domain <- [plain, tenant], {_path, src} <- LiveView.render_all(domain) do
        assert {:ok, _} = Code.string_to_quoted(src)
      end
    end

    test "includes the CUSTOM marker", %{plain: domain} do
      {_path, src} =
        LiveView.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/index.ex") end)

      assert src =~ Caravela.Gen.Custom.marker()
    end
  end

  describe "Caravela.Gen.LiveView --with-domain" do
    test "emits a FormDomain sibling module per entity", %{plain: domain} do
      files = LiveView.render_all(domain, with_domain: true)
      paths = Enum.map(files, &elem(&1, 0))

      # 3 entities × (index + show + form + form_domain) = 12 files
      assert length(files) == 12

      assert Enum.any?(paths, &String.ends_with?(&1, "book_live/form_domain.ex"))
      assert Enum.any?(paths, &String.ends_with?(&1, "author_live/form_domain.ex"))
    end

    test "form LiveView switches to the Template-backed variant", %{plain: domain} do
      {_path, src} =
        LiveView.render_all(domain, with_domain: true)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/form.ex") end)

      assert src =~ "use Caravela.Live.Template, domain: MyAppWeb.Library.BookLive.FormDomain"
      assert src =~ "apply_updater(socket, :mark_saving)"
      assert src =~ "apply_updater(socket, :set_errors,"
    end

    test "generated mount/3 seeds defaults before apply_updater(:load, ...)",
         %{plain: domain} do
      # Regression for: "KeyError :errors" on first mount. The mount body
      # must call __assign_defaults__ before the first apply_updater so
      # every key from the domain's state block (e.g. :errors, :attrs)
      # exists on socket.assigns.
      {_path, src} =
        LiveView.render_all(domain, with_domain: true)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/form.ex") end)

      assert src =~ "__caravela_live_state__"
      assert src =~ "Caravela.Live.Template.__assign_defaults__"

      [_, mount_body] = String.split(src, "def mount(params, _session, socket) do", parts: 2)
      [mount_body, _] = String.split(mount_body, "\n  end\n", parts: 2)

      assigns_idx = :binary.match(mount_body, "__assign_defaults__") |> elem(0)
      updater_idx = :binary.match(mount_body, "apply_updater(:load") |> elem(0)

      assert assigns_idx < updater_idx,
             "defaults must be seeded before the :load updater runs"
    end

    test "FormDomain uses Caravela.Live.Domain and declares the expected updaters",
         %{plain: domain} do
      {_path, src} =
        LiveView.render_all(domain, with_domain: true)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/form_domain.ex") end)

      assert src =~ "defmodule MyAppWeb.Library.BookLive.FormDomain do"
      assert src =~ "use Caravela.Live.Domain"
      assert src =~ "state do"

      for name <- [
            ":mark_saving",
            ":mark_saved",
            ":set_errors",
            ":set_flash",
            ":put_attr",
            ":load"
          ] do
        assert src =~ "updater #{name}, fn"
      end
    end

    test "all --with-domain files are valid Elixir", %{plain: plain, tenant: tenant} do
      for domain <- [plain, tenant],
          {_path, src} <- LiveView.render_all(domain, with_domain: true) do
        assert {:ok, _} = Code.string_to_quoted(src)
      end
    end

    test "without --with-domain the form stays plain (no Template use)", %{plain: domain} do
      {_path, src} =
        LiveView.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/form.ex") end)

      refute src =~ "Caravela.Live.Template"
    end
  end

  describe "Caravela.Gen.LiveRoute" do
    test "emits a browser scope with four routes per entity", %{plain: domain} do
      snippet = Caravela.Gen.LiveRoute.render(domain)

      assert snippet =~ ~s|scope "/library", MyAppWeb do|
      assert snippet =~ "pipe_through :browser"

      for route <- [
            ~s|live "/books", BookLive.Index, :index|,
            ~s|live "/books/new", BookLive.Form, :new|,
            ~s|live "/books/:id", BookLive.Show, :show|,
            ~s|live "/books/:id/edit", BookLive.Form, :edit|
          ] do
        assert snippet =~ route
      end
    end

    test "versioned domain yields /v1 prefix and V1 alias", %{tenant: domain} do
      snippet = Caravela.Gen.LiveRoute.render(domain)

      assert snippet =~ ~s|scope "/v1/tenant_library", MyAppWeb.V1 do|
    end
  end

  describe "Caravela.Gen.Svelte — TypeScript interfaces" do
    test "generates a single types file per domain", %{plain: domain} do
      {path, src} = Svelte.render_types(domain)

      assert path == "assets/svelte/types/library.ts"
      assert src =~ "export interface Book {"
      assert src =~ "export interface Author {"
      assert src =~ "export interface Publisher {"
    end

    test "fields follow TS nullability rules", %{plain: domain} do
      {_path, src} = Svelte.render_types(domain)

      # Required → no `?`
      assert src =~ "title: string;"
      # Optional → `?:`
      assert src =~ "isbn?: string;"
      assert src =~ "published?: boolean;"
      # Decimal → string
      assert src =~ "price?: string;"
    end

    test "tenant_id is hidden from the public interface", %{tenant: domain} do
      {_path, src} = Svelte.render_types(domain)
      refute src =~ "tenant_id"
    end

    test "versioned types live under assets/svelte/v1/types/", %{tenant: domain} do
      {path, _src} = Svelte.render_types(domain)
      assert path == "assets/svelte/v1/types/tenant_library.ts"
    end

    test "types file includes the CUSTOM marker", %{plain: domain} do
      {_path, src} = Svelte.render_types(domain)
      assert src =~ "// --- CUSTOM ---"
    end
  end

  describe "Caravela.Gen.Svelte — components" do
    test "generates index, show, and form per entity", %{plain: domain} do
      paths =
        Svelte.render_components(domain)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      assert Enum.any?(paths, &(&1 == "assets/svelte/library/BookIndex.svelte"))
      assert Enum.any?(paths, &(&1 == "assets/svelte/library/BookShow.svelte"))
      assert Enum.any?(paths, &(&1 == "assets/svelte/library/BookForm.svelte"))
      # 3 entities × 3 kinds
      assert length(paths) == 9
    end

    test "index imports the TS interface from ../types/<context>", %{plain: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookIndex.svelte") end)

      assert src =~ "import type { Book } from '../types/library';"
      assert src =~ "books?: Book[];"
      assert src =~ "= $props();"
      assert src =~ "{#each books as book (book.id)}"
      assert src =~ "pushEvent('delete', { id });"
    end

    test "form emits one input per public field, marked required when required", %{plain: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookForm.svelte") end)

      # Required field gets the asterisk label + inclusion
      assert src =~ "Title *"
      # Optional field has no asterisk
      assert src =~ ~r/>\n    Isbn\n/
      # Boolean uses a checkbox input
      assert src =~ ~s|type="checkbox"|
    end

    test "tenant_id is hidden from the form inputs", %{tenant: domain} do
      {_path, src} =
        Svelte.render_components(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "BookForm.svelte") end)

      refute src =~ "tenant_id"
    end

    test "svelte components have the <!-- --- CUSTOM --- --> marker", %{plain: domain} do
      for {_path, src} <- Svelte.render_components(domain) do
        assert src =~ "<!-- --- CUSTOM --- -->"
      end
    end
  end
end
