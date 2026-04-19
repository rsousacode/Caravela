defmodule Mix.Tasks.Caravela.InfoTest do
  use ExUnit.Case, async: true

  alias Caravela.IR
  alias Mix.Tasks.Caravela.Info

  describe "render/2" do
    setup do
      {:ok, ir: IR.of(MyApp.Domains.Library)}
    end

    test "header mentions the domain module and Caravela version", %{ir: ir} do
      out = Info.render(ir, false)
      assert out =~ "MyApp.Domains.Library"
      assert out =~ "Caravela 0.9"
    end

    test "prints the domain flags block", %{ir: ir} do
      out = Info.render(ir, false)
      assert out =~ "multi-tenant:"
      assert out =~ "default policy:"
      assert out =~ "api version:"
    end

    test "lists every entity with its module, table, and fields", %{ir: ir} do
      out = Info.render(ir, false)

      for e <- ir.entities do
        assert out =~ e.name
        assert out =~ e.module
        assert out =~ e.table

        for f <- e.fields do
          assert out =~ f.name, "expected #{f.name} in output"
        end
      end
    end

    test "fields show `required` flag when applicable", %{ir: ir} do
      out = Info.render(ir, false)
      # `title` on :books is required in the fixture.
      assert out =~ "title (string, required"
    end

    test "fields show opts when present", %{ir: ir} do
      out = Info.render(ir, false)
      # `title` has min_length: 3.
      assert out =~ "min_length=3"
    end

    test "relations section shows the entity's outbound + inbound relations", %{ir: ir} do
      out = Info.render(ir, false)
      # books has belongs_to → authors (inverse of the declared has_many).
      assert out =~ "belongs_to → authors"
      assert out =~ "has_many → books"
    end

    test "entity with a declared policy block shows a one-line summary", %{ir: ir} do
      out = Info.render(ir, false)
      assert out =~ ~r/policy:.*scope/
    end

    test "entity without a policy shows '—'", %{ir: ir} do
      out = Info.render(ir, false)

      # authors has no policy.
      authors_block =
        out |> String.split("\n\n") |> Enum.find(&String.contains?(&1, "authors\n"))

      assert authors_block =~ "policy:     —"
    end

    test "totals footer shows counts", %{ir: ir} do
      out = Info.render(ir, false)
      assert out =~ ~r/Hooks: \d+/
      assert out =~ ~r/Relations: \d+/
    end

    test "color: false emits no ANSI escape codes", %{ir: ir} do
      out = Info.render(ir, false)
      refute out =~ "\e["
    end

    test "color: true includes ANSI escape codes", %{ir: ir} do
      out = Info.render(ir, true)
      assert out =~ "\e["
    end
  end

  describe "auth rendering" do
    test "authenticatable entity lists strategies and extras" do
      ir = IR.of(MyApp.Domains.Identity)
      out = Info.render(ir, false)

      assert out =~ ~r/auth:.*password/
      assert out =~ ~r/auth:.*api_token/
      assert out =~ ~r/auth:.*session/
      assert out =~ "on_register"
    end
  end

  describe "multi-tenant reporting" do
    test "tenant domain reports multi-tenant: yes" do
      out = IR.of(MyApp.Domains.TenantLibrary) |> Info.render(false)
      assert out =~ "multi-tenant:   yes"
    end

    test "non-tenant domain reports multi-tenant: no" do
      out = IR.of(MyApp.Domains.Library) |> Info.render(false)
      assert out =~ "multi-tenant:   no"
    end
  end
end
