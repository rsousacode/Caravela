defmodule Caravela.Gen.LiveRoute do
  @moduledoc """
  Renders the `live` router snippet for a Caravela domain's generated
  LiveViews, analogous to `Caravela.Gen.RouterScope` for the JSON API.

  Caravela does not edit `router.ex` automatically. Instead, the mix
  task prints the exact `scope` + `live` lines and the developer pastes
  them. Routes mirror the generator's own path convention:

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

  @doc "Return the router snippet for `live` routes as a string."
  def render(%Domain{} = domain) do
    web_mod = Naming.web_module(domain)
    ctx_short = Naming.context_short(domain)

    {scope_prefix, scope_module} =
      case Domain.version(domain) do
        nil -> {"/" <> ctx_short, web_mod}
        v -> {"/#{v}/#{ctx_short}", Module.concat(web_mod, Macro.camelize(v))}
      end

    lines =
      domain.entities
      |> Enum.flat_map(&routes_for_entity/1)
      |> Enum.join("\n")

    """
    # Paste into lib/#{scope_app_dir(domain)}_web/router.ex under your :browser pipeline:

    scope #{inspect(scope_prefix)}, #{inspect(scope_module)} do
      pipe_through :browser

    #{lines}
    end
    """
  end

  defp routes_for_entity(%Entity{name: name}) do
    path = "/" <> Naming.plural_string(name)
    short = Naming.camelize(Naming.singularize(name))

    [
      ~s|  live "#{path}", #{short}Live.Index, :index|,
      ~s|  live "#{path}/new", #{short}Live.Form, :new|,
      ~s|  live "#{path}/:id", #{short}Live.Show, :show|,
      ~s|  live "#{path}/:id/edit", #{short}Live.Form, :edit|
    ]
  end

  defp scope_app_dir(%Domain{} = domain) do
    [root | _] = domain.module |> Naming.context_module() |> Module.split()
    Macro.underscore(root)
  end
end
