defmodule Mix.Tasks.Caravela.Mcp do
  @shortdoc "Start the Caravela MCP server on stdio"

  @moduledoc """
  Start the [Model Context Protocol](https://modelcontextprotocol.io)
  server for the current Caravela project on stdio.

      mix caravela.mcp

  Intended to be launched by an MCP host (Claude Code, Cursor, Zed,
  etc.) that owns the process's stdin/stdout. Runs until stdin
  closes.

  ## Configuring a host

  Claude Code `~/.claude/claude_desktop_config.json`:

      {
        "mcpServers": {
          "caravela": {
            "command": "mix",
            "args": ["caravela.mcp"],
            "cwd": "/absolute/path/to/your/phoenix/project"
          }
        }
      }

  Equivalent entries work for Cursor, Zed, and any other
  MCP-speaking host.

  ## What the host can do

  Once connected, the host exposes these tools to the LLM:

    * `caravela__describe_domain` - full IR for a domain module
    * `caravela__list_entities` - entity names in a domain
    * `caravela__describe_entity` - IR for one entity
    * `caravela__validate_dsl` - compile a candidate DSL and report
      structured errors

  See `Caravela.MCP` for the full tool list and wire format.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    # Compile the project so the consumer's domain modules are
    # available for introspection.
    Mix.Task.run("compile", ["--no-return-errors"])
    Mix.shell().info("[caravela.mcp] serving on stdio - Ctrl-D to stop.")

    Caravela.MCP.serve()
  end
end
