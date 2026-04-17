defmodule Caravela.Phase2GenTest do
  use ExUnit.Case, async: false

  alias Caravela.Gen.{Context, Controller, Custom, RouterScope}

  setup do
    domain = MyApp.Domains.Library.__caravela_domain__()
    {:ok, domain: domain}
  end

  describe "Caravela.Gen.Context" do
    test "writes a single file at the expected path", %{domain: domain} do
      {path, _source} = Context.render(domain)
      assert path == "lib/my_app/library.ex"
    end

    test "defines CRUD functions per entity", %{domain: domain} do
      {_path, source} = Context.render(domain)

      for fn_name <- ~w(
            list_authors get_author get_author! change_author
            create_author update_author delete_author
            list_books   get_book   get_book!   change_book
            create_book  update_book delete_book
            list_publishers get_publisher get_publisher!
          ) do
        assert source =~ "def #{fn_name}(",
               "missing function #{fn_name} in generated context:\n#{source}"
      end
    end

    test "read path applies can_read permission", %{domain: domain} do
      {_path, source} = Context.render(domain)
      assert source =~ "apply_read_permission(:books, context)"
      assert source =~ ~s|:can_read, entity, query, context|
    end

    test "create path authorizes and runs on_create hook", %{domain: domain} do
      {_path, source} = Context.render(domain)
      assert source =~ "authorize_create(:books, context)"
      assert source =~ "apply_changeset_hook(:on_create, :books, context)"
    end

    test "update path authorizes, applies changeset hook, updates", %{domain: domain} do
      {_path, source} = Context.render(domain)
      assert source =~ "authorize_update(:books, book, context)"
      assert source =~ "apply_changeset_hook(:on_update, :books, context)"
    end

    test "delete path authorizes and runs on_delete hook", %{domain: domain} do
      {_path, source} = Context.render(domain)
      assert source =~ "authorize_delete(:books, book, context)"
      assert source =~ "run_delete_hook(:books, book, context)"
    end

    test "aliases the domain module for dispatch", %{domain: domain} do
      {_path, source} = Context.render(domain)
      assert source =~ "MyApp.Domains.Library.__caravela_permission__"
      assert source =~ "MyApp.Domains.Library.__caravela_hook__"
    end

    test "generated context is syntactically valid Elixir", %{domain: domain} do
      {_path, source} = Context.render(domain)
      assert {:ok, _ast} = Code.string_to_quoted(source)
    end

    test "includes the CUSTOM marker", %{domain: domain} do
      {_path, source} = Context.render(domain)
      assert source =~ Custom.marker()
    end
  end

  describe "Caravela.Gen.Controller" do
    test "writes one file per entity", %{domain: domain} do
      files = Controller.render_all(domain)
      paths = Enum.map(files, fn {p, _} -> p end)

      assert Enum.sort(paths) == [
               "lib/my_app_web/controllers/author_controller.ex",
               "lib/my_app_web/controllers/book_controller.ex",
               "lib/my_app_web/controllers/publisher_controller.ex"
             ]
    end

    test "book controller has all REST actions", %{domain: domain} do
      {_path, source} =
        Controller.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_controller.ex") end)

      for action <- ~w(index show create update delete) do
        assert source =~ "def #{action}(",
               "missing action #{action} in controller:\n#{source}"
      end
    end

    test "controller delegates to the context module", %{domain: domain} do
      {_path, source} =
        Controller.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_controller.ex") end)

      assert source =~ "alias MyApp.Library"
      assert source =~ "Library.list_books(context)"
      assert source =~ "Library.create_book(attrs, context)"
      assert source =~ "Library.update_book(entity, attrs, context)"
      assert source =~ "Library.delete_book(entity, context)"
    end

    test "controller returns 201 on create, 403 on unauthorized, 422 on changeset error", %{
      domain: domain
    } do
      {_path, source} =
        Controller.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_controller.ex") end)

      assert source =~ "put_status(:created)"
      assert source =~ "put_status(:forbidden)"
      assert source =~ "put_status(:unprocessable_entity)"
      assert source =~ "put_status(:not_found)"
    end

    test "generated controllers are syntactically valid Elixir", %{domain: domain} do
      for {_path, source} <- Controller.render_all(domain) do
        assert {:ok, _ast} = Code.string_to_quoted(source)
      end
    end

    test "includes the CUSTOM marker", %{domain: domain} do
      {_path, source} =
        Controller.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_controller.ex") end)

      assert source =~ Custom.marker()
    end
  end

  describe "Caravela.Gen.RouterScope" do
    test "emits a scope /api snippet with one resources line per entity", %{domain: domain} do
      snippet = RouterScope.render(domain)

      assert snippet =~ ~s|scope "/api", MyAppWeb do|
      assert snippet =~ "pipe_through :api"
      assert snippet =~ ~s|resources "/authors", AuthorController|
      assert snippet =~ ~s|resources "/books", BookController|
      assert snippet =~ ~s|resources "/publishers", PublisherController|
    end

    test "scope ends with an `end` line", %{domain: domain} do
      snippet = RouterScope.render(domain)
      assert String.trim_trailing(snippet) |> String.ends_with?("end")
    end
  end

  describe "Caravela.Gen.Custom" do
    test "merge preserves content below the marker when regenerating" do
      existing = """
      defmodule Foo do
        def old, do: :old

        # --- CUSTOM ---
        # Custom code below this line is preserved on regeneration.
        def user_added, do: :kept
      end
      """

      regenerated = """
      defmodule Foo do
        def new, do: :new

        # --- CUSTOM ---
        # Custom code below this line is preserved on regeneration.
      end
      """

      merged = Custom.merge(regenerated, existing)

      assert merged =~ "def new, do: :new"
      refute merged =~ "def old, do: :old"
      assert merged =~ "def user_added, do: :kept"
    end

    test "merge is a no-op when the existing file lacks the marker" do
      existing = "defmodule Foo do\n  def x, do: 1\nend\n"
      regenerated = "defmodule Foo do\n  def y, do: 2\nend\n"

      assert Custom.merge(regenerated, existing) == regenerated
    end

    test "merge_with_file returns new source when file is missing" do
      regenerated = "defmodule Foo do\n  # --- CUSTOM ---\nend\n"
      assert Custom.merge_with_file(regenerated, "/no/such/file.ex") == regenerated
    end

    test "end-to-end: context regeneration preserves user code", %{domain: domain} do
      {path, source_v1} = Context.render(domain)

      # Simulate a user adding code below the marker.
      custom_addition =
        source_v1
        |> String.replace(
          Custom.marker() <> "\n",
          Custom.marker() <>
            "\n  # Custom code below this line is preserved on regeneration.\n" <>
            "  def my_helper, do: :still_here\n"
        )

      tmp_root =
        Path.join(System.tmp_dir!(), "caravela_regen_#{System.unique_integer([:positive])}")

      target = Path.join(tmp_root, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, custom_addition)

      {_path, source_v2} = Context.render(domain, root: tmp_root)

      File.rm_rf!(tmp_root)

      assert source_v2 =~ "def my_helper, do: :still_here",
             "CUSTOM merge lost the user's code:\n#{source_v2}"
    end
  end
end
