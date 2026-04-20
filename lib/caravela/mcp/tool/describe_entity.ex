defmodule Caravela.MCP.Tool.DescribeEntity do
  @moduledoc """
  MCP tool: return the IR for a single entity within a Caravela
  domain (fields, relations, policy, auth).

  Narrow alternative to `caravela__describe_domain` when the caller
  knows which entity they want.
  """

  @behaviour Caravela.MCP.Tool

  alias Caravela.IR
  alias Caravela.MCP.Tool

  @impl true
  @spec name() :: String.t()
  def name, do: "caravela__describe_entity"

  @impl true
  @spec description() :: String.t()
  def description do
    "Return the IR for one entity within a Caravela domain - " <>
      "fields, relations (inbound + outbound), policy summary, auth config."
  end

  @impl true
  @spec input_schema() :: map()
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "domain" => %{
          "type" => "string",
          "description" => "The domain module name, e.g. \"MyApp.Domains.Library\"."
        },
        "entity" => %{
          "type" => "string",
          "description" => "Entity name as declared in the DSL (plural atom, e.g. \"books\")."
        }
      },
      "required" => ["domain", "entity"]
    }
  end

  @impl true
  @spec call(map()) :: {:ok, [map()]} | {:error, String.t()}
  def call(%{"domain" => domain_str, "entity" => entity_str})
      when is_binary(domain_str) and is_binary(entity_str) do
    with {:ok, mod} <- resolve_module(domain_str),
         :ok <- ensure_caravela_domain(mod),
         ir <- IR.of(mod),
         {:ok, entity} <- find_entity(ir, entity_str) do
      payload = %{
        entity: entity,
        relations: relations_for(ir, entity_str)
      }

      {:ok, Tool.text_content(payload)}
    end
  end

  def call(_), do: {:error, "requires `domain` and `entity` arguments"}

  defp resolve_module(name) do
    mod = Module.concat([name])

    case Code.ensure_loaded(mod) do
      {:module, ^mod} -> {:ok, mod}
      {:error, reason} -> {:error, "could not load #{name}: #{inspect(reason)}"}
    end
  end

  defp ensure_caravela_domain(mod) do
    if function_exported?(mod, :__caravela_domain__, 0) do
      :ok
    else
      {:error, "#{inspect(mod)} is not a Caravela domain (no `use Caravela.Domain`)"}
    end
  end

  defp find_entity(ir, entity_str) do
    case Enum.find(ir.entities, &(&1.name == entity_str)) do
      nil ->
        known = Enum.map_join(ir.entities, ", ", & &1.name)
        {:error, "entity #{inspect(entity_str)} not found. Known: #{known}"}

      entity ->
        {:ok, entity}
    end
  end

  defp relations_for(ir, entity_str) do
    Enum.filter(ir.relations, fn r ->
      r.from == entity_str or r.to == entity_str
    end)
  end
end
