defmodule Caravela.MCP.Tool.DescribeFrontendModeTest do
  use ExUnit.Case, async: true

  alias Caravela.MCP.Tool.DescribeFrontendMode

  defmodule MixedDomain do
    use Caravela.Domain, default_policy: :allow

    entity :authors do
      field :name, :string, required: true
    end

    entity :books, frontend: :rest do
      field :title, :string, required: true
    end

    entity :chapters, frontend: :rest, realtime: true do
      field :number, :integer
    end
  end

  describe "name/0 and description/0" do
    test "tool is named caravela__describe_frontend_mode" do
      assert DescribeFrontendMode.name() == "caravela__describe_frontend_mode"
    end

    test "description mentions both modes and realtime" do
      desc = DescribeFrontendMode.description()
      assert desc =~ "render transport"
      assert desc =~ "realtime"
    end
  end

  describe "input_schema/0" do
    test "requires :domain and accepts optional :entity" do
      schema = DescribeFrontendMode.input_schema()
      assert schema["required"] == ["domain"]
      assert Map.has_key?(schema["properties"], "entity")
    end
  end

  describe "call/1" do
    test "returns every entity's mode when only :domain is given" do
      {:ok, [%{"type" => "text", "text" => text}]} =
        DescribeFrontendMode.call(%{"domain" => inspect(MixedDomain)})

      {:ok, payload} = Jason.decode(text)

      assert payload["domain"] == inspect(MixedDomain)
      assert length(payload["entities"]) == 3

      by_name = Map.new(payload["entities"], &{&1["name"], &1})

      assert by_name["authors"]["frontend"] == "live"
      assert by_name["authors"]["realtime"] == false
      assert by_name["books"]["frontend"] == "rest"
      assert by_name["books"]["realtime"] == false
      assert by_name["chapters"]["frontend"] == "rest"
      assert by_name["chapters"]["realtime"] == true
    end

    test "narrows to a single entity when :entity is provided" do
      {:ok, [%{"type" => "text", "text" => text}]} =
        DescribeFrontendMode.call(%{
          "domain" => inspect(MixedDomain),
          "entity" => "chapters"
        })

      {:ok, payload} = Jason.decode(text)

      assert payload["entity"]["name"] == "chapters"
      assert payload["entity"]["frontend"] == "rest"
      assert payload["entity"]["realtime"] == true
      assert is_list(payload["entity"]["notes"])
    end

    test "reports a clear error when the entity is unknown" do
      assert {:error, msg} =
               DescribeFrontendMode.call(%{
                 "domain" => inspect(MixedDomain),
                 "entity" => "widgets"
               })

      assert msg =~ "not found"
      assert msg =~ "authors"
    end

    test "fails gracefully on a missing domain module" do
      assert {:error, msg} =
               DescribeFrontendMode.call(%{"domain" => "Caravela.NoSuchDomain"})

      assert msg =~ "could not load"
    end

    test "requires the :domain argument" do
      assert {:error, msg} = DescribeFrontendMode.call(%{})
      assert msg =~ "domain"
    end
  end

  describe "registered on the MCP tool list" do
    test "appears in Caravela.MCP.Tool.registry/0" do
      assert DescribeFrontendMode in Caravela.MCP.Tool.registry()
    end
  end
end
