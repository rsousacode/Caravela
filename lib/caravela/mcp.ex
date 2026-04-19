defmodule Caravela.MCP do
  @moduledoc """
  [Model Context Protocol](https://modelcontextprotocol.io) server for
  Caravela.

  Exposes Caravela's IR, DSL validator, and entity metadata as
  structured tools an LLM client (Claude Code, Cursor, Zed, any
  MCP-speaking host) can call instead of guessing DSL syntax.

  ## Transport

  JSON-RPC 2.0 over stdio. Each message is a single line of JSON. Start
  the server in a consumer project with:

      mix caravela.mcp

  The client connects over the process's stdin/stdout. HTTP transport
  (for remote / team-shared MCP) is deferred to a future release.

  ## Tools shipped in 0.10

    * `caravela__describe_domain` — full IR for a domain module.
    * `caravela__list_entities` — entity names for a domain module.
    * `caravela__describe_entity` — IR for one entity.
    * `caravela__validate_dsl` — compile a candidate domain DSL and
      report structured errors.

  All tools are read-only or sandboxed; none mutate source files.

  ## Why an MCP server

  Before MCP: an LLM writing Caravela domains had to memorize the DSL
  or hallucinate it. Error messages (structured in 0.9.x) help, but the
  model still guesses at syntax first.

  With MCP: the model calls `caravela__describe_entity` to see the
  existing shape, proposes a change, calls `caravela__validate_dsl` to
  catch errors before committing, and the host shows the user a
  reviewable diff. Zero-hallucination workflow.
  """

  @protocol_version "2024-11-05"

  @doc "Wire-protocol version this server speaks."
  @spec protocol_version() :: String.t()
  def protocol_version, do: @protocol_version

  @doc "Server identification block returned in `initialize`."
  @spec server_info() :: %{required(String.t()) => String.t()}
  def server_info do
    %{
      "name" => "caravela-mcp",
      "version" => to_string(Application.spec(:caravela, :vsn) || "dev")
    }
  end

  @doc """
  Start the stdio MCP server on the given IO device. Blocks until
  stdin closes.

  Uses `:stdio` by default. Tests pass a `StringIO` device to exercise
  the loop without touching the real stdin.
  """
  @spec serve(IO.device()) :: :ok
  def serve(io_device \\ :stdio) do
    Caravela.MCP.Server.run(io_device)
  end
end
