defmodule Caravela.Gen.RouterScope do
  @moduledoc """
  Renders the router scope snippet a developer needs to paste into
  their `lib/<app>_web/router.ex` after generating controllers.

  Caravela does not edit the router file automatically - the router is
  the application's own composition root. Instead, the generator prints
  the exact `scope` + `resources` lines and the developer pastes them
  in.
  """

  alias Caravela.Schema.Domain
  alias Caravela.Naming

  @doc "Return the router snippet as a string."
  def render(%Domain{} = domain) do
    web_mod = Naming.web_module(domain)

    {scope_prefix, scope_module} =
      case Domain.version(domain) do
        nil -> {"/api", web_mod}
        v -> {"/api/" <> v, Module.concat(web_mod, Macro.camelize(v))}
      end

    resources =
      domain.entities
      |> Enum.map(fn entity ->
        short = Naming.camelize(Naming.singularize(entity.name))

        "  resources #{inspect(Naming.route_path(entity.name))}, " <>
          "#{short}Controller, except: [:new, :edit]"
      end)
      |> Enum.join("\n")

    """
    # Paste into lib/#{scope_app_dir(domain)}_web/router.ex under your :api pipeline:

    scope #{inspect(scope_prefix)}, #{inspect(scope_module)} do
      pipe_through :api

    #{resources}
    end
    """
  end

  defp scope_app_dir(domain) do
    [root | _] = domain.module |> Naming.context_module() |> Module.split()
    Macro.underscore(root)
  end
end
