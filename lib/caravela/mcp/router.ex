defmodule Caravela.MCP.Router do
  @moduledoc """
  Method dispatch for the Caravela MCP server.

  Takes a decoded JSON-RPC request map and returns either a response
  map (for request-id-carrying messages) or `:notification`
  (notifications are fire-and-forget — we write nothing back).

  Supported MCP methods:

    * `initialize` — handshake, returns protocol version +
      server capabilities.
    * `notifications/initialized` — post-handshake notification.
      Acknowledged silently.
    * `tools/list` — enumerate registered tools.
    * `tools/call` — dispatch to the named tool.

  Anything else returns a `method_not_found` error.
  """

  alias Caravela.MCP
  alias Caravela.MCP.{Protocol, Tool}

  @doc """
  Handle a decoded request map. Returns either a response map to
  write back, or `:notification` / `:no_response` if nothing should
  be sent.
  """
  @spec handle(map()) :: map() | :notification | :no_response
  def handle(%{"method" => "initialize", "id" => id}) do
    Protocol.response(id, %{
      "protocolVersion" => MCP.protocol_version(),
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => MCP.server_info()
    })
  end

  def handle(%{"method" => "notifications/initialized"}) do
    :notification
  end

  def handle(%{"method" => "ping", "id" => id}) do
    Protocol.response(id, %{})
  end

  def handle(%{"method" => "tools/list", "id" => id}) do
    Protocol.response(id, %{"tools" => Tool.list()})
  end

  def handle(%{"method" => "tools/call", "id" => id, "params" => params}) do
    handle_tool_call(id, params)
  end

  def handle(%{"method" => method, "id" => id}) do
    Protocol.method_not_found(id, method)
  end

  def handle(%{"method" => _method}) do
    # Notification for an unknown method — ignore silently per JSON-RPC.
    :notification
  end

  def handle(%{"id" => id}) do
    Protocol.invalid_request(id)
  end

  def handle(_) do
    :no_response
  end

  # --- tools/call dispatch -----------------------------------------------

  defp handle_tool_call(id, %{"name" => name} = params) when is_binary(name) do
    args = Map.get(params, "arguments", %{})

    case Tool.find(name) do
      nil ->
        Protocol.invalid_params(id, "unknown tool: #{name}")

      tool_mod ->
        invoke_tool(id, tool_mod, args)
    end
  end

  defp handle_tool_call(id, _params) do
    Protocol.invalid_params(id, "tools/call requires `name` and optional `arguments`")
  end

  defp invoke_tool(id, tool_mod, args) do
    case tool_mod.call(args) do
      {:ok, content} when is_list(content) ->
        Protocol.response(id, %{"content" => content, "isError" => false})

      {:error, message} when is_binary(message) ->
        Protocol.response(id, %{
          "content" => Tool.plain_text(message),
          "isError" => true
        })
    end
  rescue
    e ->
      Protocol.response(id, %{
        "content" => Tool.plain_text("tool raised: #{Exception.message(e)}"),
        "isError" => true
      })
  end
end
