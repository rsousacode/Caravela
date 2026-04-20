# MCP server

Caravela ships a [Model Context Protocol](https://modelcontextprotocol.io)
server that exposes the compiled domain as a set of tools an LLM host
can call. With the server running, Claude Code / Cursor / Zed / any
MCP-compliant host stops guessing the DSL and reads the IR directly.

## Launching

```bash
mix caravela.mcp
```

The task compiles the project (so domain modules are loadable), then
speaks JSON-RPC 2.0 over stdio, one message per line. Protocol
version `2024-11-05`.

No daemon, no port. The host owns process lifecycle - typically
spawning one per workspace.

### Claude Code / Claude Desktop

```jsonc
// ~/.claude/claude_desktop_config.json
{
  "mcpServers": {
    "caravela": {
      "command": "mix",
      "args": ["caravela.mcp"],
      "cwd": "/absolute/path/to/your/project"
    }
  }
}
```

Restart the host; Caravela's tools appear under the project's MCP
server. Other MCP-compliant clients take a similar `{command, args,
cwd}` shape.

## Tool surface

Every tool name is prefixed `caravela__` so multiple MCP servers can
coexist without collision. Inputs / outputs are JSON maps matching
the IR schema ([`Caravela.IR`](../lib/caravela/ir.ex)).

| Tool                               | Input                          | Returns                                                               |
|------------------------------------|--------------------------------|-----------------------------------------------------------------------|
| `caravela__describe_domain`        | `{domain: "MyApp.Domains.X"}`  | Full IR: entities, fields, relations, policies, auth, hooks           |
| `caravela__list_entities`          | `{domain}`                     | Entity names declared on the domain, in DSL order                     |
| `caravela__describe_entity`        | `{domain, entity: "books"}`    | One entity's IR plus its relations (inbound + outbound)               |
| `caravela__describe_frontend_mode` | `{domain, entity?}`            | Render transport (`:live` / `:rest`), `realtime?` flag, per-mode notes |
| `caravela__validate_dsl`           | `{source: "defmodule …"}`      | `{:ok}` or `{:error, [DSLError]}` - parse a candidate domain file without compiling it into the project |

All tools read from the *current* compiled IR. Modify the DSL, recompile,
and subsequent tool calls see the new shape. No caching.

## Why use it

An LLM editing a Caravela app without MCP guesses at module names,
DSL spellings, and policy shapes from whatever it saw in its
training. With MCP it reads the actual IR of the actual project, and
its suggestions reference real entities / fields / relations.
Concretely:

- **No hallucinated function names.** The LLM sees that
  `MyApp.Library.list_books/1` exists because
  `caravela__describe_entity` returns its public API.
- **No guessed render mode.** Asked "add a delete button to
  BookIndex", the LLM first calls `caravela__describe_frontend_mode`
  to confirm whether `books` is served as `:live` (`live.pushEvent`)
  or `:rest` (`useForm` / `navigate`) - those have different client
  patterns.
- **Pre-validated DSL changes.** Before proposing a DSL patch, the
  LLM can call `caravela__validate_dsl` on the candidate source and
  catch errors without the user hitting compile in a loop.

## Context for the rest of the plan

The MCP server is 9 of [llm_friendliness.md](https://github.com/rsousacode/caravela-plan/blob/main/features/llm_friendliness.md) and composes
with the other LLM-grounding deliverables:

- **Structured errors** ([4](https://github.com/rsousacode/caravela-plan/blob/main/features/llm_friendliness.md) - shipped v0.9.0): every
  `Caravela.DSLError` carries `:message`, `:snippet`, `:suggestion`,
  and `:docs_url`. `caravela__validate_dsl` returns them verbatim.
- **Unified check** (`mix caravela.check` - shipped v0.9.1): one
  oracle for "is this correct?" - hosts that want a pass/fail
  instead of per-tool inspection call this.
- **JSON IR** (`mix caravela.ir` + `Caravela.IR.of/1` - shipped
  v0.9.0): the same structure the MCP tools return, dumpable to a
  file for grounding RAG systems or fine-tuning corpora.

The eval harness, `mix caravela.new --from "<prompt>"`, and the
cookbook are still open on that plan; see
[llm_friendliness.md](https://github.com/rsousacode/caravela-plan/blob/main/features/llm_friendliness.md) for the roadmap.

## Security

The stdio transport shipped in Caravela 0.10+ is local-only. An HTTP
transport for team / shared MCP scenarios is out of 1.1 scope and
will require explicit auth. Write-capable tools (tools that would
modify files rather than just read the IR) are also out of scope
until after 1.0 - the current tool surface is read-only plus one
sandbox validator.
