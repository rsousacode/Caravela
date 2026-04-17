defmodule Caravela.Phase3GraphQLTest do
  use ExUnit.Case, async: false

  alias Caravela.Gen.GraphQL

  setup do
    {:ok,
     plain: MyApp.Domains.Library.__caravela_domain__(),
     tenant: MyApp.Domains.TenantLibrary.__caravela_domain__()}
  end

  describe "Caravela.Gen.GraphQL file paths" do
    test "non-versioned domain writes three files under schema/", %{plain: domain} do
      paths = GraphQL.render_all(domain) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

      assert paths == [
               "lib/my_app_web/schema/library_mutations.ex",
               "lib/my_app_web/schema/library_queries.ex",
               "lib/my_app_web/schema/library_types.ex"
             ]
    end

    test "versioned domain writes files under schema/v1/", %{tenant: domain} do
      paths = GraphQL.render_all(domain) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

      assert paths == [
               "lib/my_app_web/schema/v1/tenant_library_mutations.ex",
               "lib/my_app_web/schema/v1/tenant_library_queries.ex",
               "lib/my_app_web/schema/v1/tenant_library_types.ex"
             ]
    end
  end

  describe "Caravela.Gen.GraphQL types" do
    test "object types cover every entity with an id and the declared scalars", %{plain: domain} do
      {_path, source} = GraphQL.render_types(domain)

      assert source =~ "object :book do"
      assert source =~ "field :id, non_null(:id)"
      assert source =~ "field :title, non_null(:string)"
      assert source =~ "field :isbn, :string"
      assert source =~ "field :published, :boolean"
      assert source =~ "field :price, :decimal"
    end

    test "relations resolve through dataloader against the context module", %{plain: domain} do
      {_path, source} = GraphQL.render_types(domain)

      assert source =~ "field :books, list_of(:book), resolve: dataloader(MyApp.Library)"
      assert source =~ "field :author, :author, resolve: dataloader(MyApp.Library)"
      assert source =~ "field :publisher, :publisher, resolve: dataloader(MyApp.Library)"
    end

    test "tenant_id is NOT exposed as a public field", %{tenant: domain} do
      {_path, source} = GraphQL.render_types(domain)
      refute source =~ "field :tenant_id"
    end

    test "versioned types dataloader targets the versioned context module", %{tenant: domain} do
      {_path, source} = GraphQL.render_types(domain)
      assert source =~ "dataloader(MyApp.TenantLibrary.V1)"
      assert source =~ "defmodule MyAppWeb.Schema.V1.TenantLibraryTypes do"
    end

    test "types file is valid Elixir", %{plain: plain, tenant: tenant} do
      for domain <- [plain, tenant] do
        {_path, source} = GraphQL.render_types(domain)
        assert {:ok, _ast} = Code.string_to_quoted(source)
      end
    end
  end

  describe "Caravela.Gen.GraphQL queries" do
    test "queries include list + single-fetch per entity", %{plain: domain} do
      {_path, source} = GraphQL.render_queries(domain)

      assert source =~ "field :books, list_of(:book)"
      assert source =~ "field :book, :book"
      assert source =~ "Library.list_books(extract_context(resolution))"
      assert source =~ "Library.get_book(id, extract_context(resolution))"
    end

    test "versioned queries alias the versioned context", %{tenant: domain} do
      {_path, source} = GraphQL.render_queries(domain)
      assert source =~ "alias MyApp.TenantLibrary.V1"
      assert source =~ "V1.list_books(extract_context(resolution))"
    end

    test "queries file is valid Elixir", %{plain: plain, tenant: tenant} do
      for domain <- [plain, tenant] do
        {_path, source} = GraphQL.render_queries(domain)
        assert {:ok, _ast} = Code.string_to_quoted(source)
      end
    end
  end

  describe "Caravela.Gen.GraphQL mutations" do
    test "input objects exclude tenant_id", %{tenant: domain} do
      {_path, source} = GraphQL.render_mutations(domain)

      assert source =~ "input_object :book_input do"
      refute source =~ "field :tenant_id"
    end

    test "mutations provide create / update / delete per entity", %{plain: domain} do
      {_path, source} = GraphQL.render_mutations(domain)

      assert source =~ "field :create_book, :book"
      assert source =~ "field :update_book, :book"
      assert source =~ "field :delete_book, :book"

      assert source =~ "Library.create_book(input, extract_context(resolution))"
      assert source =~ "Library.get_book(id, context)"
      assert source =~ "Library.update_book(entity, input, context)"
      assert source =~ "Library.delete_book(entity, context)"
    end

    test "mutations format :unauthorized as a user-friendly error", %{plain: domain} do
      {_path, source} = GraphQL.render_mutations(domain)
      assert source =~ ~s|defp format_error(:unauthorized), do: "unauthorized"|
    end

    test "mutations file is valid Elixir", %{plain: plain, tenant: tenant} do
      for domain <- [plain, tenant] do
        {_path, source} = GraphQL.render_mutations(domain)
        assert {:ok, _ast} = Code.string_to_quoted(source)
      end
    end
  end

  describe "Caravela.Gen.GraphQL CUSTOM marker" do
    test "every generated file includes the CUSTOM marker", %{tenant: domain} do
      for {_path, source} <- GraphQL.render_all(domain) do
        assert source =~ Caravela.Gen.Custom.marker()
      end
    end
  end
end
