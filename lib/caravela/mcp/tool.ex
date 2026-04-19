defmodule Caravela.MCP.Tool do
  @moduledoc """
  Behaviour + registry for Caravela MCP tools.

  A tool module implements:

    * `name/0` — the wire-level tool name, exposed to the MCP client.
      By convention, prefix with `caravela__` so tools show up
      grouped in host UIs.
    * `description/0` — short prose explaining what the tool does.
    * `input_schema/0` — JSON Schema for the tool's arguments.
    * `call/1` — invoke the tool; returns structured content or an
      error.

  ## Return shape

  `call/1` returns either `{:ok, content}` or `{:error, message}`.

  `content` is a list of MCP content items. The common case is a
  single text item containing JSON:

      {:ok, [%{"type" => "text", "text" => Jason.encode!(payload)}]}

  The server wraps the result into the `{content: [...], isError:
  false}` shape MCP clients expect.
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback call(args :: map()) ::
              {:ok, content :: [map()]} | {:error, message :: String.t()}

  @doc """
  The list of tool modules the server exposes. Add new tools here;
  the server picks them up automatically.
  """
  @spec registry() :: [module()]
  def registry do
    [
      Caravela.MCP.Tool.DescribeDomain,
      Caravela.MCP.Tool.ListEntities,
      Caravela.MCP.Tool.DescribeEntity,
      Caravela.MCP.Tool.DescribeFrontendMode,
      Caravela.MCP.Tool.ValidateDsl
    ]
  end

  @doc "Look up a tool module by its wire-level name."
  @spec find(String.t()) :: module() | nil
  def find(name) when is_binary(name) do
    Enum.find(registry(), fn mod -> mod.name() == name end)
  end

  @doc """
  The MCP `tools/list` response shape — one entry per registered
  tool with its name, description, and input schema.
  """
  @spec list() :: [map()]
  def list do
    Enum.map(registry(), fn mod ->
      %{
        "name" => mod.name(),
        "description" => mod.description(),
        "inputSchema" => mod.input_schema()
      }
    end)
  end

  @doc """
  Helper: wrap a JSON-serializable term as a single text-content
  item. Tools use this to return structured payloads (their JSON
  shape shows up to the LLM as the `text` of the content item).
  """
  @spec text_content(term()) :: [map()]
  def text_content(term) do
    [%{"type" => "text", "text" => Jason.encode!(term, pretty: true)}]
  end

  @doc "Helper: wrap a plain string as a single text-content item."
  @spec plain_text(String.t()) :: [map()]
  def plain_text(text) when is_binary(text) do
    [%{"type" => "text", "text" => text}]
  end
end
