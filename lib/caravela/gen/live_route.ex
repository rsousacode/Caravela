defmodule Caravela.Gen.LiveRoute do
  @moduledoc """
  Renders router snippets for a Caravela domain's generated frontend
  routes — one block per render mode:

    * `:live` entities get `live` routes under the `:browser` pipeline
      (today's LiveView + WebSocket path).
    * `:rest` entities get `caravela_rest` routes under the `:browser`
      pipeline, served via `caravela_svelte`'s Inertia-style HTTP
      transport. The router macro is imported from
      `CaravelaSvelte.Router`; this snippet prints the lines the
      developer pastes, it doesn't require `caravela_svelte` to be
      compiled at generation time.

  Caravela does not edit `router.ex` automatically — these snippets
  are printed by `mix caravela.gen.live` for the developer to paste
  into their app's composition root.

  Routes mirror the generator's own path convention:

      /library/books
      /library/books/new
      /library/books/:id
      /library/books/:id/edit

  When the domain declares `version "v1"`, the scope prefix shifts to
  `/v1/library/...` and the web-module alias picks up the `V1.` segment,
  matching `Caravela.Gen.LiveView`'s module layout.
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

  defp rest_routes_for_entity(%Entity{name: name}) do
    path = "/" <> Naming.plural_string(name)
    short = Naming.camelize(Naming.singularize(name))

    [
      ~s|  caravela_rest "#{path}", #{short}Controller|
    ]
  end

  defp scope_app_dir(%Domain{} = domain) do
    [root | _] = domain.module |> Naming.context_module() |> Module.split()
    Macro.underscore(root)
  end
end
