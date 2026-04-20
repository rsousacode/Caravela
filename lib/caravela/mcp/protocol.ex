defmodule Caravela.MCP.Protocol do
  @moduledoc """
  JSON-RPC 2.0 message encoding, decoding, and builders for the
  Caravela MCP server.

  Stdio MCP transport is one JSON message per line: every frame is
  serialized with a trailing newline; every incoming line parses as a
  complete message. No Content-Length framing (that's the LSP
  convention, not MCP's).

  The standard error codes follow JSON-RPC 2.0:

    * `-32700` Parse error - invalid JSON was received
    * `-32600` Invalid Request - not a valid request object
    * `-32601` Method not found
    * `-32602` Invalid params
    * `-32603` Internal error
  """

  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603

  @doc "Encode a message as a newline-terminated JSON string."
  @spec encode(map()) :: iodata()
  def encode(message) when is_map(message) do
    [Jason.encode!(message), "\n"]
  end

  @doc """
  Decode a single JSON-RPC message from a line of input. Returns
  `{:ok, map}` on success or `{:error, reason}` on malformed JSON.
  """
  @spec decode(String.t()) :: {:ok, map()} | {:error, term()}
  def decode(line) when is_binary(line) do
    Jason.decode(line)
  end

  @doc "Build a JSON-RPC 2.0 success response."
  @spec response(term(), map() | list() | String.t() | number() | boolean() | nil) :: map()
  def response(id, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  @doc """
  Build a JSON-RPC 2.0 error response. `code` is a JSON-RPC error
  code (see moduledoc); `data` is an optional arbitrary term attached
  to help the client diagnose.
  """
  @spec error(term(), integer(), String.t(), term()) :: map()
  def error(id, code, message, data \\ nil) do
    err = %{"code" => code, "message" => message}
    err = if is_nil(data), do: err, else: Map.put(err, "data", data)
    %{"jsonrpc" => "2.0", "id" => id, "error" => err}
  end

  @doc "Shorthand: `-32700` parse error response."
  @spec parse_error(term()) :: map()
  def parse_error(id \\ nil), do: error(id, @parse_error, "Parse error")

  @doc "Shorthand: `-32600` invalid request."
  @spec invalid_request(term()) :: map()
  def invalid_request(id \\ nil), do: error(id, @invalid_request, "Invalid Request")

  @doc "Shorthand: `-32601` method not found."
  @spec method_not_found(term(), String.t()) :: map()
  def method_not_found(id, method),
    do: error(id, @method_not_found, "Method not found: #{method}")

  @doc "Shorthand: `-32602` invalid params."
  @spec invalid_params(term(), String.t()) :: map()
  def invalid_params(id, detail),
    do: error(id, @invalid_params, "Invalid params: #{detail}")

  @doc "Shorthand: `-32603` internal error."
  @spec internal_error(term(), String.t()) :: map()
  def internal_error(id, detail),
    do: error(id, @internal_error, "Internal error: #{detail}")

  @doc "True if the request carries an id field (i.e. expects a response)."
  @spec request?(map()) :: boolean()
  def request?(%{"id" => _}), do: true
  def request?(_), do: false
end
