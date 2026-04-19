defmodule Caravela.Gen.LiveRoute do
  @moduledoc """
  Pure-string router-snippet renderer — a debugging / legacy helper.

  > #### Superseded in v0.12 {: .warning}
  >
  > Caravela-generated apps register routes through the
  > `Caravela.Router` macro (`caravela_routes/1`), which expands from
  > the DSL at compile time. The `mix caravela.gen.live` task prints a
  > one-line hint pointing at that macro instead of a paste-snippet.
  >
  > This module still renders the old paste-snippet string so scripts
  > and introspection tools that want a textual representation of a
  > domain's router shape can get one. New code should use
  > `Caravela.Router` directly.

  Emits one block per render mode:

    * `:live` entities get `live "/<plural>", <Entity>Live.<Kind>`
      lines under a `:browser` pipeline scope.
    * `:rest` entities get `caravela_rest "/<plural>",
      <Entity>Controller` (with `realtime: true` when the entity
      opts in).

  When the domain declares `version "v1"`, the scope prefix shifts
  to `/v1/<context>/...` and the web-module alias picks up the
  `V1.` segment, matching `Caravela.Gen.LiveView`'s module layout.
  """

  alias Caravela.Schema.{Domain, Entity}
  alias Caravela.Naming

  @doc """
  Return the router snippet covering every entity's frontend mode.

  When the domain mixes `:live` and `:rest` entities, both blocks are
  printed. When every entity shares the same mode, only that block is
  printed. A domain with no entities returns an empty string.
  """
  def render(%Domain{} = domain) do
    {scope_prefix, scope_module} = scope(domain)

    live_entities = Enum.filter(domain.entities, &(&1.frontend == :live))
    rest_entities = Enum.filter(domain.entities, &(&1.frontend == :rest))

    [
      render_block(:live, live_entities, scope_prefix, scope_module, domain),
      render_block(:rest, rest_entities, scope_prefix, scope_module, domain)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp render_block(_mode, [], _prefix, _module, _domain), do: ""

  defp render_block(:live, entities, scope_prefix, scope_module, domain) do
    lines =
      entities
      |> Enum.flat_map(&live_routes_for_entity/1)
      |> Enum.join("\n")

    """
    # Paste into lib/#{scope_app_dir(domain)}_web/router.ex under your :browser pipeline:

    scope #{inspect(scope_prefix)}, #{inspect(scope_module)} do
      pipe_through :browser

    #{lines}
    end
    """
  end

  defp render_block(:rest, entities, scope_prefix, scope_module, domain) do
    lines =
      entities
      |> Enum.flat_map(&rest_routes_for_entity/1)
      |> Enum.join("\n")

    """
    # Paste into lib/#{scope_app_dir(domain)}_web/router.ex under your :browser pipeline.
    # Requires `import CaravelaSvelte.Router` at the top of the router module.

    scope #{inspect(scope_prefix)}, #{inspect(scope_module)} do
      pipe_through :browser

    #{lines}
    end
    """
  end

  defp scope(%Domain{} = domain) do
    web_mod = Naming.web_module(domain)
    ctx_short = Naming.context_short(domain)

    case Domain.version(domain) do
      nil -> {"/" <> ctx_short, web_mod}
      v -> {"/#{v}/#{ctx_short}", Module.concat(web_mod, Macro.camelize(v))}
    end
  end

  defp live_routes_for_entity(%Entity{name: name}) do
    path = "/" <> Naming.plural_string(name)
    short = Naming.camelize(Naming.singularize(name))

    [
      ~s|  live "#{path}", #{short}Live.Index, :index|,
      ~s|  live "#{path}/new", #{short}Live.Form, :new|,
      ~s|  live "#{path}/:id", #{short}Live.Show, :show|,
      ~s|  live "#{path}/:id/edit", #{short}Live.Form, :edit|
    ]
  end

  defp rest_routes_for_entity(%Entity{name: name, realtime?: realtime?}) do
    path = "/" <> Naming.plural_string(name)
    short = Naming.camelize(Naming.singularize(name))

    base = ~s|  caravela_rest "#{path}", #{short}Controller|
    line = if realtime?, do: base <> ", realtime: true", else: base

    [line]
  end

  defp scope_app_dir(%Domain{} = domain) do
    [root | _] = domain.module |> Naming.context_module() |> Module.split()
    Macro.underscore(root)
  end
end
