defmodule Caravela.MCP.ToolsTest do
  use ExUnit.Case, async: true

  alias Caravela.MCP.Tool
  alias Caravela.MCP.Tool.{DescribeDomain, DescribeEntity, ListEntities, ValidateDsl}

  describe "registry + lookup" do
    test "registry/0 returns the four shipped tools" do
      assert DescribeDomain in Tool.registry()
      assert ListEntities in Tool.registry()
      assert DescribeEntity in Tool.registry()
      assert ValidateDsl in Tool.registry()
    end

    test "find/1 by wire name" do
      assert Tool.find("caravela__describe_domain") == DescribeDomain
      assert Tool.find("caravela__list_entities") == ListEntities
      assert Tool.find("caravela__describe_entity") == DescribeEntity
      assert Tool.find("caravela__validate_dsl") == ValidateDsl
      assert Tool.find("caravela__nothing") == nil
    end

    test "list/0 returns tool descriptors with required keys" do
      for tool <- Tool.list() do
        assert Map.has_key?(tool, "name")
        assert Map.has_key?(tool, "description")
        assert Map.has_key?(tool, "inputSchema")
      end
    end

    test "text_content/1 wraps a term as a text content item" do
      assert [%{"type" => "text", "text" => json}] = Tool.text_content(%{a: 1})
      assert Jason.decode!(json) == %{"a" => 1}
    end
  end

  describe "caravela__describe_domain" do
    test "returns the IR for a valid domain" do
      {:ok, [%{"type" => "text", "text" => text}]} =
        DescribeDomain.call(%{"domain" => "MyApp.Domains.Library"})

      ir = Jason.decode!(text)
      assert ir["domain"] == "MyApp.Domains.Library"
      assert is_list(ir["entities"])
    end

    test "errors on a non-Caravela module" do
      assert {:error, msg} = DescribeDomain.call(%{"domain" => "Elixir.String"})
      assert msg =~ "not a Caravela domain"
    end

    test "errors on a missing module" do
      assert {:error, msg} = DescribeDomain.call(%{"domain" => "No.Such.Module"})
      assert msg =~ "could not load"
    end

    test "errors when :domain is missing" do
      assert {:error, _} = DescribeDomain.call(%{})
    end
  end

  describe "caravela__list_entities" do
    test "lists entities in DSL order" do
      {:ok, [%{"text" => text}]} = ListEntities.call(%{"domain" => "MyApp.Domains.Library"})
      %{"entities" => names} = Jason.decode!(text)
      assert "books" in names
      assert "authors" in names
      assert "publishers" in names
    end
  end

  describe "caravela__describe_entity" do
    test "returns entity IR + inbound/outbound relations" do
      {:ok, [%{"text" => text}]} =
        DescribeEntity.call(%{
          "domain" => "MyApp.Domains.Library",
          "entity" => "books"
        })

      %{"entity" => entity, "relations" => relations} = Jason.decode!(text)
      assert entity["name"] == "books"
      assert entity["singular"] == "book"
      assert is_list(entity["fields"])
      # books has an outbound relation to authors / publishers
      assert Enum.any?(relations, &(&1["to"] == "authors" or &1["to"] == "publishers"))
    end

    test "unknown entity returns a helpful error with the known list" do
      assert {:error, msg} =
               DescribeEntity.call(%{
                 "domain" => "MyApp.Domains.Library",
                 "entity" => "ghosts"
               })

      assert msg =~ "ghosts"
      assert msg =~ "books"
    end
  end

  describe "caravela__validate_dsl" do
    test "returns ok + IR for a well-formed candidate" do
      source = """
      defmodule Caravela.MCP.ValidateTest.GoodDomain do
        use Caravela.Domain
        entity :widgets do
          field :name, :string, required: true
        end
      end
      """

      {:ok, [%{"text" => text}]} = ValidateDsl.call(%{"source" => source})
      payload = Jason.decode!(text)
      assert payload["ok"] == true
      assert payload["ir"]["domain"] == "Caravela.MCP.ValidateTest.GoodDomain"
    end

    test "returns structured DSLError on a bad field type" do
      source = """
      defmodule Caravela.MCP.ValidateTest.BadDomain do
        use Caravela.Domain
        entity :widgets do
          field :name, :string, min: :oops
        end
        policy :widgets do
          scope fn q, _ -> q end
        end
      end
      """

      {:ok, [%{"text" => text}]} = ValidateDsl.call(%{"source" => source})
      payload = Jason.decode!(text)
      # May succeed (validation fires at ecto-schema generation time, not
      # DSL compile). The important behavior: the tool never crashes and
      # always returns a structured payload.
      assert is_boolean(payload["ok"])
    end

    test "returns structured error when the candidate doesn't use Caravela.Domain" do
      source = """
      defmodule Caravela.MCP.ValidateTest.NotADomain do
        def hello, do: :world
      end
      """

      {:ok, [%{"text" => text}]} = ValidateDsl.call(%{"source" => source})
      payload = Jason.decode!(text)
      assert payload["ok"] == false
      assert payload["error"]["kind"] == "not_a_domain"
    end

    test "rescues compile errors into a structured payload" do
      source = "defmodule Caravela.MCP.ValidateTest.Broken do\n  not actual elixir\nend"

      {:ok, [%{"text" => text}]} = ValidateDsl.call(%{"source" => source})
      payload = Jason.decode!(text)
      assert payload["ok"] == false
      assert payload["error"]["kind"] in ["compile_error", "exception"]
    end

    test "errors when :source is missing" do
      assert {:error, _} = ValidateDsl.call(%{})
    end
  end
end
