defmodule Caravela.MCP.Tool.ListEntities do
  @moduledoc """
  MCP tool: list the entity names declared by a Caravela domain.

  Cheap introspection - callers use this to discover what's in a
  domain before drilling into a specific entity with
  `caravela__describe_entity`.
  """

  @behaviour Caravela.MCP.Tool

  alias Caravela.IR
  alias Caravela.MCP.Tool

  @impl true
  @spec name() :: String.t()
  def name, do: "caravela__list_entities"

  @impl true
  @spec description() :: String.t()
  def description do
    "List entity names declared by a Caravela domain, in DSL order."
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
      ir = IR.of(mod)
      names = Enum.map(ir.entities, & &1.name)
      {:ok, Tool.text_content(%{entities: names})}
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
