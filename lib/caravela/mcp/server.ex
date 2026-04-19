defmodule Caravela.MCP.Server do
  @moduledoc """
  Stdio event loop for the Caravela MCP server.

  Reads one JSON-RPC message per line from the IO device, dispatches
  to `Caravela.MCP.Router.handle/1`, writes any response back on the
  same device. Loops until stdin closes (`:eof`) or the IO device
  errors.

  Split from `Caravela.MCP.Router` for testability: the router is
  pure (map → map), the server wraps it with IO effects. Tests
  exercise `handle_line/2` against an in-memory IO device.
  """

  alias Caravela.MCP.{Protocol, Router}

  @doc """
  Run the server, reading from `io_device` until EOF. Each message
  is a single line of JSON.
  """
  @spec run(IO.device()) :: :ok
  def run(io_device \\ :stdio) do
    case IO.read(io_device, :line) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line when is_binary(line) ->
        handle_line(line, io_device)
        run(io_device)
    end
  end

  @doc """
  Handle a single received line: decode, dispatch, write the
  response (if any) back to `io_device`. Malformed JSON yields a
  parse-error response.

  Exposed for tests; production callers use `run/1`.
  """
  @spec handle_line(String.t(), IO.device()) :: :ok
  def handle_line(line, io_device) do
    trimmed = String.trim(line)

    if trimmed == "" do
      :ok
    else
      dispatch_line(trimmed, io_device)
    end
  end

  defp dispatch_line(line, io_device) do
    case Protocol.decode(line) do
      {:ok, message} ->
        handle_message(message, io_device)

      {:error, _} ->
        write(io_device, Protocol.parse_error())
    end
  end

  defp handle_message(message, io_device) do
    case Router.handle(message) do
      %{} = response -> write(io_device, response)
      :notification -> :ok
      :no_response -> :ok
    end
  end

  defp write(io_device, message) do
    IO.write(io_device, Protocol.encode(message))
    :ok
  end
end
