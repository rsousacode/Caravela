defmodule Caravela.MCP.ProtocolTest do
  use ExUnit.Case, async: true

  alias Caravela.MCP.Protocol

  describe "encode/1" do
    test "emits newline-terminated JSON" do
      out =
        Protocol.encode(%{"jsonrpc" => "2.0", "id" => 1, "result" => "ok"})
        |> IO.iodata_to_binary()

      assert String.ends_with?(out, "\n")
      assert {:ok, %{"id" => 1, "result" => "ok"}} = Jason.decode(String.trim(out))
    end
  end

  describe "decode/1" do
    test "parses valid JSON" do
      assert {:ok, %{"jsonrpc" => "2.0", "id" => 1}} =
               Protocol.decode(~s({"jsonrpc":"2.0","id":1}))
    end

    test "returns error on malformed JSON" do
      assert {:error, _} = Protocol.decode("not-json")
    end
  end

  describe "response builders" do
    test "response/2 shape" do
      assert %{"jsonrpc" => "2.0", "id" => 42, "result" => %{"x" => 1}} =
               Protocol.response(42, %{"x" => 1})
    end

    test "error/3 with code + message" do
      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "error" => %{"code" => -32_601, "message" => msg}
             } = Protocol.method_not_found(1, "foo")

      assert msg =~ "foo"
    end

    test "error/4 attaches data when provided" do
      err = Protocol.error(1, -32_602, "bad", %{"detail" => "x"})
      assert err["error"]["data"] == %{"detail" => "x"}
    end

    test "error/4 omits data when nil" do
      err = Protocol.error(1, -32_602, "bad")
      refute Map.has_key?(err["error"], "data")
    end
  end

  describe "request?/1" do
    test "true when :id present" do
      assert Protocol.request?(%{"id" => 1, "method" => "x"})
    end

    test "false for notifications" do
      refute Protocol.request?(%{"method" => "x"})
    end
  end
end
