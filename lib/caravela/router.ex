defmodule Caravela.Router do
  @moduledoc """
  Router macros that register a Caravela domain's frontend routes at
  compile time. The router stays in sync with the domain's DSL — add
  an entity, regenerate, restart the server, and the routes exist.

  Replaces the paste-snippet workflow shipped through v0.11: instead
  of `mix caravela.gen.live` printing `live "/books", …` lines for
  the developer to paste into `router.ex`, the developer writes one
  line and the macro expands into the full route list based on each
  entity's `frontend` / `realtime?` declaration.

  ## Usage

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        use Caravela.Router
        import CaravelaSvelte.Router  # needed for :rest entities

        scope "/", MyAppWeb.Library do
          pipe_through :browser
          caravela_routes MyApp.Domains.Library
        end
      end

  Inside the scope, `caravela_routes/1` expands into:

    * `live "/<plural>", <Entity>Live.Index, :index` (and `:new`,
      `:show`, `:edit`) for every `frontend: :live` entity.
    * `caravela_rest "/<plural>", <Entity>Controller` (plus
      `realtime: true` when the entity opts in) for every
      `frontend: :rest` entity.

  Module names stay *unqualified* in the expansion so Phoenix's
  scope `alias:` resolution kicks in — drop the `caravela_routes`
  call inside a `scope Foo.BookWeb.Library do … end` and
  `BookLive.Index` becomes `Foo.BookWeb.Library.BookLive.Index`,
  matching what `Caravela.Gen.LiveView` emits.

  ## Options

  `caravela_routes/2` accepts the same options as Phoenix's
  `live_session/2` — pass them through when grouping multiple
  entities behind a common `on_mount` hook:

      caravela_routes MyApp.Domains.Library,
        session: [on_mount: {MyAppWeb.Auth, :require_user}]

  `:session` is a keyword list passed verbatim to Phoenix's
  `live_session/3`. When present, the expansion wraps the `:live`
  routes in a `live_session` block so every generated LiveView
  participates in the shared session.

  ## Versioned domains

  A domain declared with `version "v1"` names its modules
  `MyApp.Library.V1.Book` etc. The macro respects that — it emits
  `V1.BookLive.Index` so Phoenix's scope alias keeps resolution
  working across both plain and versioned layouts.
  """

  alias Caravela.Naming
  alias Caravela.Schema.{Domain, Entity}

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Caravela.Router, only: [caravela_routes: 1, caravela_routes: 2]
    end
  end

  @doc """
  Register every route for a Caravela domain.

  Expanded at compile time by loading the domain module (via
  `Code.ensure_compiled!/1`) and reading its entity list. See
  moduledoc for full semantics.
  """
  defmacro caravela_routes(domain_ast, opts \\ []) do
    domain_mod = Macro.expand(domain_ast, __CALLER__)
    Code.ensure_compiled!(domain_mod)

    unless function_exported?(domain_mod, :__caravela_domain__, 0) do
      raise Caravela.DSLError,
        message:
          "caravela_routes/1 expects a module that `use Caravela.Domain`, " <>
            "got: #{inspect(domain_mod)}",
        suggestion: "caravela_routes MyApp.Domains.Library",
        docs_url: "https://hexdocs.pm/caravela/Caravela.Router.html"
    end

    domain = domain_mod.__caravela_domain__()
    expand_routes(domain, opts)
  end

  @doc false
  @spec expand_routes(Domain.t(), keyword()) :: Macro.t()
  def expand_routes(%Domain{} = domain, opts) do
    live_entities = Enum.filter(domain.entities, &(&1.frontend == :live))
    rest_entities = Enum.filter(domain.entities, &(&1.frontend == :rest))
    version_segment = Domain.version_segment(domain)

    live_block = live_block(live_entities, version_segment, opts)
    rest_block = rest_block(rest_entities, version_segment)

    # Return a do-block even when one side is empty so the macro
    # always expands to valid AST — Phoenix.Router tolerates empty
    # route accumulators fine.
    quote do
      unquote(live_block)
      unquote(rest_block)
    end
  end

  # --- :live routes ------------------------------------------------------

  defp live_block([], _version_segment, _opts), do: empty_ast()

  defp live_block(entities, version_segment, opts) do
    routes =
      Enum.flat_map(entities, &live_routes_for_entity(&1, version_segment))

    case Keyword.get(opts, :session) do
      nil ->
        quote do
          (unquote_splicing(routes))
        end

      session_opts when is_list(session_opts) ->
        quote do
          live_session unquote(live_session_name(entities)), unquote(session_opts) do
            (unquote_splicing(routes))
          end
        end
    end
  end

  defp live_session_name(entities) do
    entities
    |> Enum.map(& &1.name)
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join("_")
    |> then(&("caravela_live_" <> &1))
    |> String.to_atom()
  end

  defp live_routes_for_entity(%Entity{name: name}, version_segment) do
    path = "/" <> Naming.plural_string(name)
    short = Naming.camelize(Naming.singularize(name))
    live_mod = module_alias_ast(["#{short}Live"], version_segment)

    [
      quote do
        live(unquote(path), unquote(child(live_mod, :Index)), :index)
      end,
      quote do
        live(unquote(path <> "/new"), unquote(child(live_mod, :Form)), :new)
      end,
      quote do
        live(unquote(path <> "/:id"), unquote(child(live_mod, :Show)), :show)
      end,
      quote do
        live(unquote(path <> "/:id/edit"), unquote(child(live_mod, :Form)), :edit)
      end
    ]
  end

  # --- :rest routes ------------------------------------------------------

  defp rest_block([], _version_segment), do: empty_ast()

  defp rest_block(entities, version_segment) do
    routes =
      Enum.map(entities, &rest_route_for_entity(&1, version_segment))

    quote do
      (unquote_splicing(routes))
    end
  end

  defp rest_route_for_entity(%Entity{name: name, realtime?: realtime?}, version_segment) do
    path = "/" <> Naming.plural_string(name)
    short = Naming.camelize(Naming.singularize(name))
    controller = module_alias_ast(["#{short}Controller"], version_segment)

    if realtime? do
      quote do
        caravela_rest(unquote(path), unquote(controller), realtime: true)
      end
    else
      quote do
        caravela_rest(unquote(path), unquote(controller))
      end
    end
  end

  # --- AST helpers -------------------------------------------------------

  # Build an unqualified alias AST like `V1.BookLive` so Phoenix's
  # scope `alias:` wraps it with the calling scope's module prefix.
  defp module_alias_ast(parts, nil), do: aliases(parts)

  defp module_alias_ast(parts, version_segment) do
    aliases([version_segment | parts])
  end

  defp aliases(parts) when is_list(parts) do
    atoms = Enum.map(parts, &String.to_atom/1)
    {:__aliases__, [alias: false], atoms}
  end

  # Append a trailing atom segment to an alias AST.
  defp child({:__aliases__, meta, parts}, segment) when is_atom(segment) do
    {:__aliases__, meta, parts ++ [segment]}
  end

  # An AST that expands to nothing — keeps the outer quote block
  # well-formed when a given render mode has no entities.
  defp empty_ast do
    quote do
      _ = :ok
    end
  end
end
