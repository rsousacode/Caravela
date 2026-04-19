defmodule Caravela.MCP.RouterTest do
  use ExUnit.Case, async: true

  alias Caravela.MCP.Router

  describe "initialize" do
    test "returns protocol version + capabilities + server info" do
      resp =
        Router.handle(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{"protocolVersion" => "2024-11-05"}
        })

      assert %{
               "id" => 1,
               "result" => %{
                 "protocolVersion" => _,
                 "capabilities" => %{"tools" => %{}},
                 "serverInfo" => %{"name" => "caravela-mcp", "version" => _}
               }
             } = resp
    end
  end

  describe "notifications/initialized" do
    test "is acknowledged silently (no response)" do
      assert :notification =
               Router.handle(%{
                 "jsonrpc" => "2.0",
                 "method" => "notifications/initialized"
               })
    end
  end

  describe "ping" do
    test "responds with an empty result" do
      resp = Router.handle(%{"jsonrpc" => "2.0", "id" => 99, "method" => "ping"})
      assert %{"id" => 99, "result" => %{}} = resp
    end
  end

  describe "tools/list" do
    test "returns every registered tool with name + description + inputSchema" do
      resp = Router.handle(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"})
      assert %{"result" => %{"tools" => tools}} = resp
      assert is_list(tools) and length(tools) >= 4

      names = Enum.map(tools, & &1["name"])
      assert "caravela__describe_domain" in names
      assert "caravela__list_entities" in names
      assert "caravela__describe_entity" in names
      assert "caravela__validate_dsl" in names

      for t <- tools do
        assert is_binary(t["name"])
        assert is_binary(t["description"]) and t["description"] != ""
        assert is_map(t["inputSchema"])
      end
    end
  end

  describe "tools/call" do
    test "dispatches to an existing tool and wraps the result" do
      resp =
        Router.handle(%{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "tools/call",
          "params" => %{
            "name" => "caravela__list_entities",
            "arguments" => %{"domain" => "MyApp.Domains.Library"}
          }
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => text}], "isError" => false}} =
               resp

      payload = Jason.decode!(text)
      assert is_list(payload["entities"])
      assert "books" in payload["entities"]
    end

    test "unknown tool returns invalid_params error" do
      resp =
        Router.handle(%{
          "jsonrpc" => "2.0",
          "id" => 4,
          "method" => "tools/call",
          "params" => %{"name" => "caravela__nonexistent", "arguments" => %{}}
        })

      assert %{"error" => %{"code" => -32_602, "message" => msg}} = resp
      assert msg =~ "unknown tool"
    end

    test "tool returning {:error, _} is surfaced as isError: true" do
      resp =
        Router.handle(%{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => "tools/call",
          "params" => %{
            "name" => "caravela__describe_domain",
            "arguments" => %{"domain" => "Nonexistent.Module"}
          }
        })

      assert %{"result" => %{"content" => [%{"text" => msg}], "isError" => true}} = resp
      assert msg =~ "could not load"
    end

    test "missing arguments returns invalid_params" do
      resp =
        Router.handle(%{
          "jsonrpc" => "2.0",
          "id" => 6,
          "method" => "tools/call",
          "params" => %{}
        })

      assert %{"error" => %{"code" => -32_602}} = resp
    end
  end

  describe "unknown method" do
    test "returns method_not_found for requests with an id" do
      resp =
        Router.handle(%{
          "jsonrpc" => "2.0",
          "id" => 7,
          "method" => "unknown/method"
        })

      assert %{"error" => %{"code" => -32_601, "message" => msg}} = resp
      assert msg =~ "unknown/method"
    end

    test "silently ignores unknown notifications (no id)" do
      assert :notification =
               Router.handle(%{"jsonrpc" => "2.0", "method" => "unknown/method"})
    end
  end
end
