defmodule Caravela.GenTest do
  use ExUnit.Case, async: false

  alias Caravela.Gen.{EctoSchema, Migration}

  setup do
    domain = MyApp.Domains.Library.__caravela_domain__()
    {:ok, domain: domain}
  end

  describe "Caravela.Gen.EctoSchema" do
    test "renders one file per entity with expected paths", %{domain: domain} do
      files = EctoSchema.render_all(domain)
      paths = Enum.map(files, fn {p, _} -> p end)

      assert Enum.sort(paths) == [
               "lib/my_app/library/author.ex",
               "lib/my_app/library/book.ex",
               "lib/my_app/library/publisher.ex"
             ]
    end

    test "book schema has both declared belongs_to (publisher) and inferred belongs_to (author)",
         %{domain: domain} do
      {_, book_source} =
        EctoSchema.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book.ex") end)

      assert book_source =~ ~s|schema "library_books"|
      assert book_source =~ "belongs_to :publisher, MyApp.Library.Publisher"
      assert book_source =~ "belongs_to :author, MyApp.Library.Author"
      assert book_source =~ ~s|validate_length(:title, min: 3)|
      assert book_source =~ ~s|validate_format(:isbn, ~r/^\\d{13}$/)|
      assert book_source =~ ~s|foreign_key_constraint(:author_id)|
      assert book_source =~ ~s|foreign_key_constraint(:publisher_id)|
    end

    test "author schema has has_many :books on inferred side", %{domain: domain} do
      {_, author_source} =
        EctoSchema.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "author.ex") end)

      assert author_source =~ "has_many :books, MyApp.Library.Book"
      assert author_source =~ ~s|@required_fields [:name]|
    end

    test "publisher schema has has_many :books from inverse of belongs_to", %{domain: domain} do
      {_, pub_source} =
        EctoSchema.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "publisher.ex") end)

      assert pub_source =~ "has_many :books, MyApp.Library.Book"
    end

    test "no parens on field/belongs_to/has_many after formatting", %{domain: domain} do
      {_, book_source} =
        EctoSchema.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book.ex") end)

      assert book_source =~ "field :title, :string"
      refute book_source =~ "field(:title"
      refute book_source =~ "belongs_to("
    end

    test "generated code is syntactically valid Elixir", %{domain: domain} do
      for {_path, source} <- EctoSchema.render_all(domain) do
        assert {:ok, _ast} = Code.string_to_quoted(source)
      end
    end

    test "generated schemas compile cleanly (Ecto.Schema accepts them)", %{domain: domain} do
      # Wrap the generated sources into unique namespaces to avoid
      # re-defining modules across test runs.
      suffix = "T#{System.unique_integer([:positive])}"

      sources =
        domain
        |> EctoSchema.render_all()
        |> Enum.map(fn {_path, s} ->
          s
          |> String.replace("MyApp.Library", "MyApp.#{suffix}.Library")
          |> String.replace("library_", "library_#{String.downcase(suffix)}_")
        end)

      {_results, io} =
        ExUnit.CaptureIO.with_io(:stderr, fn ->
          Enum.each(sources, &Code.compile_string/1)
        end)

      refute io =~ "warning:", "generated schemas produced warnings:\n#{io}"
    end
  end

  describe "Caravela.Gen.Migration" do
    test "produces a single migration file with expected path", %{domain: domain} do
      {path, _source} = Migration.render(domain, timestamp: "20260417120000")
      assert path == "priv/repo/migrations/20260417120000_create_library_tables.exs"
    end

    test "tables are created in dependency order (parents before children)", %{domain: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")

      authors_pos = index_of(source, "create table(:library_authors")
      publishers_pos = index_of(source, "create table(:library_publishers")
      books_pos = index_of(source, "create table(:library_books")

      assert authors_pos, "expected :library_authors create statement"
      assert publishers_pos, "expected :library_publishers create statement"
      assert books_pos, "expected :library_books create statement"

      assert authors_pos < books_pos
      assert publishers_pos < books_pos
    end

    test "migration includes references and indexes for foreign keys", %{domain: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")

      assert source =~ "references(:library_authors"
      assert source =~ "references(:library_publishers"
      assert source =~ "create index(:library_books, [:author_id])"
      assert source =~ "create index(:library_books, [:publisher_id])"
    end

    test "required fields get null: false", %{domain: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")
      assert source =~ ~r/add :name, :string, null: false/
    end

    test "optional fields omit null: false", %{domain: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")
      # `add :bio, :text` with no trailing options → no null: false
      assert source =~ ~r/add :bio, :text\b/
    end

    test "decimal precision/scale are emitted", %{domain: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")
      assert source =~ ~r/add :price, :decimal.*precision: 10.*scale: 2/
    end

    test "migration is syntactically valid Elixir", %{domain: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")
      assert {:ok, _ast} = Code.string_to_quoted(source)
    end
  end

  defp index_of(haystack, needle) do
    case :binary.match(haystack, needle) do
      {pos, _} -> pos
      :nomatch -> nil
    end
  end
end
