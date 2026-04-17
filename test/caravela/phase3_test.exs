defmodule Caravela.Phase3Test do
  use ExUnit.Case, async: false

  alias Caravela.Gen.{Context, Controller, EctoSchema, Migration, RouterScope}
  alias Caravela.Schema.Domain
  alias Caravela.Tenant

  setup do
    {:ok,
     plain: MyApp.Domains.Library.__caravela_domain__(),
     tenant: MyApp.Domains.TenantLibrary.__caravela_domain__()}
  end

  describe "DSL opts + version" do
    test "multi_tenant: true is recorded on the Domain IR", %{tenant: domain, plain: plain} do
      assert Domain.multi_tenant?(domain)
      refute Domain.multi_tenant?(plain)
    end

    test "version is recorded on the Domain IR", %{tenant: domain, plain: plain} do
      assert Domain.version(domain) == "v1"
      assert Domain.version_segment(domain) == "V1"
      assert Domain.version(plain) == nil
      assert Domain.version_segment(plain) == nil
    end
  end

  describe "compiler validations" do
    test "rejects invalid version formats" do
      assert_raise CompileError, ~r/version "release-1" is invalid/, fn ->
        defmodule BadVersion do
          use Caravela.Domain
          version "release-1"

          entity :things do
            field :name, :string
          end
        end
      end
    end

    test "rejects manual tenant_id when multi_tenant is on" do
      assert_raise CompileError, ~r/tenant_id is auto-injected/, fn ->
        defmodule Collision do
          use Caravela.Domain, multi_tenant: true

          entity :things do
            field :tenant_id, :binary_id
            field :name, :string
          end
        end
      end
    end

    test "accepts bare version numbers like v1, v2, v42" do
      defmodule V42 do
        use Caravela.Domain
        version "v42"

        entity :things do
          field :name, :string
        end
      end

      assert Domain.version(V42.__caravela_domain__()) == "v42"
    end
  end

  describe "tenant injection" do
    test "every entity gets a :tenant_id field", %{tenant: domain} do
      for entity <- domain.entities do
        assert Enum.any?(entity.fields, &(&1.name == :tenant_id)),
               "entity #{inspect(entity.name)} missing :tenant_id"
      end
    end

    test "injected field is binary_id + required + marked tenant: true", %{tenant: domain} do
      [entity | _] = domain.entities
      tenant_field = Enum.find(entity.fields, &(&1.name == :tenant_id))

      assert tenant_field.type == :binary_id
      assert Keyword.get(tenant_field.opts, :required) == true
      assert Tenant.injected?(tenant_field)
    end

    test "non-tenant domain has no :tenant_id field injected", %{plain: domain} do
      refute Enum.any?(domain.entities, fn e ->
               Enum.any?(e.fields, &(&1.name == :tenant_id))
             end)
    end
  end

  describe "Caravela.Gen.EctoSchema + version + tenant" do
    test "versioned schema files live under v1/", %{tenant: domain} do
      paths = EctoSchema.render_all(domain) |> Enum.map(&elem(&1, 0))

      assert Enum.sort(paths) == [
               "lib/my_app/tenant_library/v1/author.ex",
               "lib/my_app/tenant_library/v1/book.ex"
             ]
    end

    test "versioned schema module is <Context>.V1.<Entity>", %{tenant: domain} do
      {_path, source} =
        EctoSchema.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book.ex") end)

      assert source =~ "defmodule MyApp.TenantLibrary.V1.Book do"
      assert source =~ "MyApp.TenantLibrary.V1.Author"
    end

    test "table name stays version-free (tables are shared)", %{tenant: domain} do
      {_path, source} =
        EctoSchema.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book.ex") end)

      assert source =~ ~s|schema "tenant_library_books"|
    end

    test "tenant_id is a declared schema field", %{tenant: domain} do
      {_path, source} =
        EctoSchema.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book.ex") end)

      assert source =~ "field :tenant_id, :binary_id"
    end

    test "tenant_id is NOT in the cast changeset", %{tenant: domain} do
      {_path, source} =
        EctoSchema.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book.ex") end)

      refute source =~ "@required_fields [:tenant_id"
      refute source =~ ":tenant_id]"
    end

    test "generated schemas are valid Elixir", %{tenant: domain} do
      for {_path, source} <- EctoSchema.render_all(domain) do
        assert {:ok, _ast} = Code.string_to_quoted(source)
      end
    end
  end

  describe "Caravela.Gen.Migration + tenant" do
    test "includes a tenant_id column with null: false", %{tenant: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")
      assert source =~ ~r/add :tenant_id, :uuid.*null: false/
    end

    test "FK indexes are composite with tenant_id for tenant-scoped tables", %{tenant: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")
      assert source =~ "create index(:tenant_library_books, [:author_id])"
      assert source =~ "create index(:tenant_library_books, [:tenant_id, :author_id])"
    end

    test "tables with no FKs still get a standalone tenant_id index", %{tenant: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")
      assert source =~ "create index(:tenant_library_authors, [:tenant_id])"
    end

    test "non-tenant domains do not get tenant_id columns or indexes", %{plain: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")
      refute source =~ "tenant_id"
    end

    test "migration is valid Elixir", %{tenant: domain} do
      {_path, source} = Migration.render(domain, timestamp: "20260417120000")
      assert {:ok, _ast} = Code.string_to_quoted(source)
    end
  end

  describe "Caravela.Gen.Context + version + tenant" do
    test "versioned context file lives under <context>/v1.ex", %{tenant: domain} do
      {path, _source} = Context.render(domain)
      assert path == "lib/my_app/tenant_library/v1.ex"
    end

    test "versioned context module is <Context>.V1", %{tenant: domain} do
      {_path, source} = Context.render(domain)
      assert source =~ "defmodule MyApp.TenantLibrary.V1 do"
    end

    test "multi-tenant context scopes reads and injects writes", %{tenant: domain} do
      {_path, source} = Context.render(domain)

      assert source =~ "scope_tenant(query, %{tenant: %{id: tenant_id}})"
      assert source =~ "where(query, [q], q.tenant_id == ^tenant_id)"
      assert source =~ "inject_tenant_id(changeset, %{tenant: %{id: tenant_id}})"
      assert source =~ "Ecto.Changeset.put_change(changeset, :tenant_id, tenant_id)"
    end

    test "non-tenant context has scope_tenant/inject_tenant_id as no-ops", %{plain: domain} do
      {_path, source} = Context.render(domain)

      assert source =~ "defp scope_tenant(query, _context), do: query"
      assert source =~ "defp inject_tenant_id(changeset, _context), do: changeset"
    end

    test "context is valid Elixir", %{tenant: domain} do
      {_path, source} = Context.render(domain)
      assert {:ok, _ast} = Code.string_to_quoted(source)
    end
  end

  describe "Caravela.Gen.Controller + version + tenant" do
    test "versioned controllers live under controllers/v1/", %{tenant: domain} do
      paths = Controller.render_all(domain) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

      assert paths == [
               "lib/my_app_web/controllers/v1/author_controller.ex",
               "lib/my_app_web/controllers/v1/book_controller.ex"
             ]
    end

    test "controller module is <Web>.V1.<Entity>Controller", %{tenant: domain} do
      {_path, source} =
        Controller.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_controller.ex") end)

      assert source =~ "defmodule MyAppWeb.V1.BookController do"
      assert source =~ "alias MyApp.TenantLibrary.V1"
    end

    test "multi-tenant controller reads conn.assigns[:tenant] into context", %{tenant: domain} do
      {_path, source} =
        Controller.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_controller.ex") end)

      assert source =~ "tenant: conn.assigns[:tenant]"
    end

    test "non-tenant controller does not include tenant: in build_context", %{plain: domain} do
      {_path, source} =
        Controller.render_all(domain)
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_controller.ex") end)

      refute source =~ "tenant: conn.assigns[:tenant]"
    end
  end

  describe "Caravela.Gen.RouterScope + version" do
    test "versioned router scope uses /api/v1 and <Web>.V1", %{tenant: domain} do
      snippet = RouterScope.render(domain)

      assert snippet =~ ~s|scope "/api/v1", MyAppWeb.V1 do|
      assert snippet =~ ~s|resources "/books", BookController|
    end

    test "non-versioned router scope stays at /api + <Web>", %{plain: domain} do
      snippet = RouterScope.render(domain)
      assert snippet =~ ~s|scope "/api", MyAppWeb do|
    end
  end
end
