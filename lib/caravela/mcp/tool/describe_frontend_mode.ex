defmodule Caravela.MCP.Tool.DescribeFrontendMode do
  @moduledoc """
  MCP tool: report the render-mode configuration for a Caravela
  domain's entities — which ones use `:live` vs `:rest`, and whether
  `:rest` entities opt into SSE realtime.

  Lets an LLM host know which transport each entity uses before
  suggesting code. Without this, a host asked "how do I add a form
  to BookIndex" can't tell whether the entity is rendered through
  LiveView's WebSocket or through `caravela_svelte`'s Inertia-style
  HTTP — and those need different client-side patterns.
  """

  @behaviour Caravela.MCP.Tool

  alias Caravela.IR
  alias Caravela.MCP.Tool

  @impl true
  @spec name() :: String.t()
  def name, do: "caravela__describe_frontend_mode"

  @impl true
  @spec description() :: String.t()
  def description do
    "Return the render transport (`:live` vs `:rest`) and realtime flag " <>
      "for every entity in a Caravela domain. Optionally narrow to a single " <>
      "entity."
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
          "description" =>
            "Optional entity name (as declared in the DSL, e.g. \"books\"). " <>
              "When omitted, returns every entity."
        }
      },
      "required" => ["domain"]
    }
  end

  @impl true
  @spec call(map()) :: {:ok, [map()]} | {:error, String.t()}
  def call(%{"domain" => domain_str} = args) when is_binary(domain_str) do
    with {:ok, mod} <- resolve_module(domain_str),
         :ok <- ensure_caravela_domain(mod) do
      ir = IR.of(mod)

      case Map.get(args, "entity") do
        nil -> {:ok, Tool.text_content(payload(ir))}
        ename when is_binary(ename) -> narrow(ir, ename)
      end
    end
  end

  def call(_), do: {:error, "missing required argument `domain`"}

  defp payload(ir) do
    %{
      domain: ir.domain,
      entities: Enum.map(ir.entities, &entity_summary/1)
    }
  end

  defp entity_summary(entity) do
    %{
      name: entity.name,
      singular: entity.singular,
      frontend: entity.frontend,
      realtime: entity.realtime,
      notes: notes_for(entity)
    }
  end

  # Terse capsule of transport-specific facts an LLM needs before
  # suggesting code. Kept short on purpose — the host can call
  # `caravela__describe_entity` for the full IR.
  defp notes_for(%{frontend: "live"}) do
    [
      "Generator emits a LiveView trio (Index / Show / Form) per " <>
        "entity, mounting `<CaravelaSvelte.svelte>`.",
      "Client-side interactivity dispatches via `live.pushEvent`."
    ]
  end

  defp notes_for(%{frontend: "rest", realtime: true}) do
    [
      "Generator emits a Phoenix controller rendering via " <>
        "`CaravelaSvelte.render/3`.",
      "Controller calls `CaravelaSvelte.Caravela.broadcast_patch/3` on " <>
        "create/update/delete; clients subscribe through " <>
        "`CaravelaSvelte.SSE`.",
      "Client-side interactivity uses `useForm` + `navigate` from " <>
        "`@caravela/svelte`."
    ]
  end

  defp notes_for(%{frontend: "rest"}) do
    [
      "Generator emits a Phoenix controller rendering via " <>
        "`CaravelaSvelte.render/3`.",
      "Client-side interactivity uses `useForm` + `navigate` from " <>
        "`@caravela/svelte`.",
      "No real-time updates — opt in via `realtime: true` on the entity."
    ]
  end

  defp narrow(ir, ename) do
    case Enum.find(ir.entities, &(&1.name == ename)) do
      nil ->
        known = Enum.map_join(ir.entities, ", ", & &1.name)
        {:error, "entity #{inspect(ename)} not found. Known: #{known}"}

      entity ->
        {:ok, Tool.text_content(%{domain: ir.domain, entity: entity_summary(entity)})}
    end
  end

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
