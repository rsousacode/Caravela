defmodule Caravela.TestGenTest do
  use ExUnit.Case, async: true

  alias Caravela.Gen.{LiveViewTest, RestControllerTest, SvelteTest}

  defmodule LibraryDomain do
    use Caravela.Domain, default_policy: :allow

    entity :authors do
      field :name, :string, required: true
    end

    entity :books, frontend: :rest do
      field :title, :string, required: true
      field :isbn, :string
    end
  end

  describe "Caravela.Gen.LiveViewTest" do
    test "emits one ExUnit file per :live entity" do
      files =
        LiveViewTest.render_all(LibraryDomain.__caravela_domain__(), root: System.tmp_dir!())

      paths = Enum.map(files, fn {p, _} -> p end)

      assert Enum.any?(paths, &String.ends_with?(&1, "author_live_test.exs"))
      refute Enum.any?(paths, &String.contains?(&1, "book_live_test.exs"))
    end

    test "covers Index/Show/Form inside a single file with describe blocks" do
      [{_path, src}] =
        LiveViewTest.render_all(LibraryDomain.__caravela_domain__(), root: System.tmp_dir!())

      # The web module + ConnCase derive from the root segment of the
      # domain module. Test only for the suffix (`.ConnCase`) so the
      # assertion survives whatever root the test domain sits under.
      assert src =~ "Web.ConnCase, async: true"
      assert src =~ "import Phoenix.LiveViewTest"
      assert src =~ ~s|describe "index"|
      assert src =~ ~s|describe "show"|
      assert src =~ ~s|describe "form - create"|
      assert src =~ ~s|describe "form - edit"|
    end

    test "carries TODO markers where user fixture wiring is expected" do
      [{_path, src}] =
        LiveViewTest.render_all(LibraryDomain.__caravela_domain__(), root: System.tmp_dir!())

      assert src =~ "# TODO:"
      assert src =~ "build_author_fixture"
    end
  end

  describe "Caravela.Gen.RestControllerTest" do
    test "emits one ExUnit file per :rest entity" do
      files =
        RestControllerTest.render_all(LibraryDomain.__caravela_domain__(),
          root: System.tmp_dir!()
        )

      paths = Enum.map(files, fn {p, _} -> p end)

      assert Enum.any?(paths, &String.ends_with?(&1, "book_controller_test.exs"))
      refute Enum.any?(paths, &String.contains?(&1, "author_controller_test.exs"))
    end

    test "emits a describe block per HTTP action with happy/unhappy tests" do
      [{_path, src}] =
        RestControllerTest.render_all(LibraryDomain.__caravela_domain__(),
          root: System.tmp_dir!()
        )

      # The route prefix derives from context_short, which for this
      # nested test domain is "library_domain". Match by suffix
      # fragments to avoid coupling to exact naming.
      assert src =~ ~s|describe "GET|
      assert src =~ "/books\""
      assert src =~ "/books/:id\""
      assert src =~ "/books/new\""
      assert src =~ "/books/:id/edit\""
      assert src =~ ~s|describe "POST|
      assert src =~ ~s|describe "PATCH|
      assert src =~ ~s|describe "DELETE|
    end

    test "references the structured-error contract in a TODO" do
      [{_path, src}] =
        RestControllerTest.render_all(LibraryDomain.__caravela_domain__(),
          root: System.tmp_dir!()
        )

      assert src =~ "Caravela.ChangesetTranslator"
    end
  end

  describe "Caravela.Gen.SvelteTest" do
    test "emits three test files per entity (index / show / form)" do
      files = SvelteTest.render_all(LibraryDomain.__caravela_domain__(), root: System.tmp_dir!())
      paths = Enum.map(files, fn {p, _} -> p end)

      assert Enum.count(paths, &String.ends_with?(&1, "AuthorIndex.test.ts")) == 1
      assert Enum.count(paths, &String.ends_with?(&1, "AuthorShow.test.ts")) == 1
      assert Enum.count(paths, &String.ends_with?(&1, "AuthorForm.test.ts")) == 1
      assert Enum.count(paths, &String.ends_with?(&1, "BookIndex.test.ts")) == 1
    end

    test "uses vitest + @testing-library/svelte imports" do
      files = SvelteTest.render_all(LibraryDomain.__caravela_domain__(), root: System.tmp_dir!())
      {_path, src} = Enum.find(files, fn {p, _} -> String.ends_with?(p, "BookIndex.test.ts") end)

      assert src =~ "from 'vitest'"
      assert src =~ "from '@testing-library/svelte'"
      assert src =~ "import BookIndex from './BookIndex.svelte'"
    end

    test "form test asserts the structured-error prop shape" do
      files = SvelteTest.render_all(LibraryDomain.__caravela_domain__(), root: System.tmp_dir!())
      {_path, src} = Enum.find(files, fn {p, _} -> String.ends_with?(p, "BookForm.test.ts") end)

      assert src =~ "code: 'required'"
      assert src =~ "params: {}"
      assert src =~ "message:"
    end
  end
end
