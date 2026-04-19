defmodule Caravela.MCP.Tool.DescribeDomain do
  @moduledoc """
  MCP tool: return the full Caravela IR for a domain module.

  Mirrors `mix caravela.ir` / `Caravela.IR.of/1` but wired as an MCP
  tool so an LLM client can fetch the IR without shelling out.
  """

  @behaviour Caravela.MCP.Tool

  alias Caravela.IR
  alias Caravela.MCP.Tool

  @impl true
  @spec name() :: String.t()
  def name, do: "caravela__describe_domain"

  @impl true
  @spec description() :: String.t()
  def description do
    "Return the full IR for a Caravela domain (entities, fields, " <>
      "relations, policies, hooks, auth config) as JSON."
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
        }
      },
      "required" => ["domain"]
    }
  end

  @impl true
  @spec call(map()) :: {:ok, [map()]} | {:error, String.t()}
  def call(%{"domain" => domain_str}) when is_binary(domain_str) do
    with {:ok, mod} <- resolve_module(domain_str),
         :ok <- ensure_caravela_domain(mod) do
      {:ok, Tool.text_content(IR.of(mod))}
    end
  end

  def call(_), do: {:error, "missing required argument `domain`"}

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
end
