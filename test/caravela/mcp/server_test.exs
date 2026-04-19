defmodule Caravela.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Caravela.MCP.Server

  describe "handle_line/2" do
    test "writes a JSON-RPC response for a valid request" do
      {:ok, out} = StringIO.open("")

      request = ~s({"jsonrpc":"2.0","id":1,"method":"ping"})
      Server.handle_line(request, out)

      {_, written} = StringIO.contents(out)
      assert String.ends_with?(written, "\n")
      assert %{"id" => 1, "result" => %{}} = Jason.decode!(String.trim(written))
    end

    test "writes a parse-error response for malformed JSON" do
      {:ok, out} = StringIO.open("")
      Server.handle_line("not-json\n", out)

      {_, written} = StringIO.contents(out)
      assert %{"error" => %{"code" => -32_700}} = Jason.decode!(String.trim(written))
    end

    test "writes nothing for notifications" do
      {:ok, out} = StringIO.open("")

      Server.handle_line(~s({"jsonrpc":"2.0","method":"notifications/initialized"}), out)

      {_, written} = StringIO.contents(out)
      assert written == ""
    end

    test "ignores empty lines" do
      {:ok, out} = StringIO.open("")
      Server.handle_line("\n", out)

      {_, written} = StringIO.contents(out)
      assert written == ""
    end
  end

  describe "run/1 event loop" do
    test "reads multiple messages until EOF" do
      input = """
      {"jsonrpc":"2.0","id":1,"method":"ping"}
      {"jsonrpc":"2.0","id":2,"method":"tools/list"}
      """

      {:ok, io} = StringIO.open(input)
      Server.run(io)

      {_, written} = StringIO.contents(io)
      responses =
        written
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert length(responses) == 2
      assert Enum.map(responses, & &1["id"]) == [1, 2]
    end

    test "survives a malformed line and continues processing" do
      input = """
      totally invalid json
      {"jsonrpc":"2.0","id":99,"method":"ping"}
      """

      {:ok, io} = StringIO.open(input)
      Server.run(io)

      {_, written} = StringIO.contents(io)

      responses =
        written
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert Enum.any?(responses, &match?(%{"error" => %{"code" => -32_700}}, &1))
      assert Enum.any?(responses, &match?(%{"id" => 99, "result" => %{}}, &1))
    end
  end

  describe "full handshake round-trip" do
    test "initialize → initialized notification → tools/list" do
      input = """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}
      {"jsonrpc":"2.0","method":"notifications/initialized"}
      {"jsonrpc":"2.0","id":2,"method":"tools/list"}
      """

      {:ok, io} = StringIO.open(input)
      Server.run(io)

      {_, written} = StringIO.contents(io)

      responses =
        written
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      # Two responses: one for initialize, one for tools/list.
      # The notifications/initialized message produces no reply.
      assert length(responses) == 2
      assert Enum.at(responses, 0)["id"] == 1
      assert Enum.at(responses, 1)["id"] == 2
      assert is_list(Enum.at(responses, 1)["result"]["tools"])
    end
  end
end
