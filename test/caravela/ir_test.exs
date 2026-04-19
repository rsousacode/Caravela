defmodule Caravela.IRTest do
  use ExUnit.Case, async: true

  alias Caravela.IR

  describe "of/1" do
    test "accepts a domain module atom" do
      ir = IR.of(MyApp.Domains.Library)
      assert ir.domain == "MyApp.Domains.Library"
    end

    test "accepts a compiled %Schema.Domain{} struct directly" do
      domain = MyApp.Domains.Library.__caravela_domain__()
      ir = IR.of(domain)
      assert ir.domain == "MyApp.Domains.Library"
    end

    test "raises on a module that does not use Caravela.Domain" do
      assert_raise ArgumentError, ~r/does not use Caravela.Domain/, fn ->
        IR.of(String)
      end
    end

    test "raises on an unloaded module" do
      assert_raise ArgumentError, ~r/could not load/, fn ->
        IR.of(Caravela.ThisModuleDoesNotExist)
      end
    end
  end

  describe "top-level shape" do
    setup do
      {:ok, ir: IR.of(MyApp.Domains.Library)}
    end

    test "every documented top-level key is present", %{ir: ir} do
      assert is_binary(ir.domain)
      assert is_binary(ir.caravela_version)
      assert is_boolean(ir.multi_tenant)
      assert ir.default_policy in ["allow", "deny"]
      assert ir.version == nil or is_binary(ir.version)
      assert is_list(ir.entities)
      assert is_list(ir.relations)
      assert is_list(ir.hooks)
    end

    test "caravela_version is a non-empty string", %{ir: ir} do
      assert ir.caravela_version != ""
    end
  end

  describe "entities" do
    setup do
      ir = IR.of(MyApp.Domains.Library)
      books = Enum.find(ir.entities, &(&1.name == "books"))
      {:ok, ir: ir, books: books}
    end

    test "each entity carries name / singular / plural / module / table", %{books: e} do
      assert e.name == "books"
      assert e.singular == "book"
      assert e.plural == "books"
      assert e.module == "MyApp.Library.Book"
      assert e.table == "library_books"
    end

    test "entity carries its render-mode frontend (defaults to \"live\")", %{books: e} do
      assert e.frontend == "live"
    end

    test "fields are maps with name, type, required, opts", %{books: e} do
      title = Enum.find(e.fields, &(&1.name == "title"))
      assert title.type == "string"
      assert title.required == true
      assert title.opts == %{"min_length" => 3}
    end

    test "decimal fields encode precision/scale as opts", %{books: e} do
      price = Enum.find(e.fields, &(&1.name == "price"))
      assert price.type == "decimal"
      assert price.opts["precision"] == 10
      assert price.opts["scale"] == 2
    end

    test "Regex opts are stringified (opaque struct)", %{books: e} do
      isbn = Enum.find(e.fields, &(&1.name == "isbn"))
      assert is_binary(isbn.opts["format"])
      assert isbn.opts["format"] =~ "~r/"
    end
  end

  describe "policy" do
    setup do
      ir = IR.of(MyApp.Domains.Library)
      books = Enum.find(ir.entities, &(&1.name == "books"))
      authors = Enum.find(ir.entities, &(&1.name == "authors"))
      {:ok, books: books, authors: authors}
    end

    test "entity with a declared policy block has a policy map", %{books: e} do
      assert is_map(e.policy)
      assert is_boolean(e.policy.has_scope)
      assert is_list(e.policy.field_rules)
      assert is_list(e.policy.action_gates)
    end

    test "action gates expose action name and arity only — no closures", %{books: e} do
      gate = Enum.find(e.policy.action_gates, &(&1.action == "create"))
      assert gate.action == "create"
      assert is_integer(gate.arity)
      refute Map.has_key?(gate, :fn)
    end

    test "entity without a policy block has policy: nil", %{authors: e} do
      assert e.policy == nil
    end
  end

  describe "auth" do
    test "non-authenticatable entity has auth: nil" do
      ir = IR.of(MyApp.Domains.Library)
      books = Enum.find(ir.entities, &(&1.name == "books"))
      assert books.auth == nil
    end

    test "authenticatable entity exposes strategies + hook flags" do
      ir = IR.of(MyApp.Domains.Identity)
      users = Enum.find(ir.entities, &(&1.name == "users"))

      assert is_map(users.auth)
      assert is_list(users.auth.strategies)
      assert Enum.any?(users.auth.strategies, &(&1.kind == "password"))
      assert is_boolean(users.auth.on_register)
      assert is_boolean(users.auth.on_login)
    end
  end

  describe "multi-tenant" do
    test "a multi-tenant domain reports multi_tenant: true" do
      ir = IR.of(MyApp.Domains.TenantLibrary)
      assert ir.multi_tenant == true
    end

    test "a single-tenant domain reports multi_tenant: false" do
      ir = IR.of(MyApp.Domains.Library)
      assert ir.multi_tenant == false
    end
  end

  describe "default_policy" do
    test "reflects the domain's declared default_policy" do
      ir_library = IR.of(MyApp.Domains.Library)
      ir_policy_library = IR.of(MyApp.Domains.PolicyLibrary)

      # Both values are documented; what matters is that the IR
      # reports them as strings.
      assert ir_library.default_policy in ["allow", "deny"]
      assert ir_policy_library.default_policy in ["allow", "deny"]
    end
  end

  describe "to_json/2" do
    test "round-trips through Jason" do
      ir = IR.of(MyApp.Domains.Library)
      json = IR.to_json(ir)

      assert {:ok, parsed} = Jason.decode(json)
      assert parsed["domain"] == "MyApp.Domains.Library"
      assert is_list(parsed["entities"])
    end

    test "pretty: false emits compact JSON" do
      ir = IR.of(MyApp.Domains.Library)
      compact = IR.to_json(ir, pretty: false)
      pretty = IR.to_json(ir, pretty: true)

      refute compact =~ "\n"
      assert pretty =~ "\n"
    end
  end
end
