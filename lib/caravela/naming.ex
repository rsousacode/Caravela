defmodule Caravela.Naming do
  @moduledoc """
  Naming conventions translating domain declarations into Elixir module
  names, file paths, and Postgres table names.

  The DSL uses plural entity names (`entity :books`). The generator
  translates them into singular module names (`Book`), plural table names
  (`library_books`), and the matching file paths under `lib/`.

  The domain module's `.Domains.` segment (if present) is stripped to
  obtain the "context module": `MyApp.Domains.Library` → `MyApp.Library`.

  When a domain declares `version "v1"`, entity and context modules are
  further namespaced under a camelized version segment
  (`MyApp.Library.V1.Book`), and matching directories appear under
  `lib/<app>/<context>/v1/...`.

  Most helpers accept either a domain module (atom) or a compiled
  `Caravela.Schema.Domain` struct. Passing the struct is required to
  pick up version-aware behaviour.
  """

  alias Caravela.Schema.Domain

  @doc """
  Context module derived from the domain module by stripping a `.Domains.`
  segment if present. When given a `Domain` struct with a declared
  version, appends the version segment.

      context_module(MyApp.Domains.Library)          #=> MyApp.Library
      context_module(%Domain{... version: "v1" ...}) #=> MyApp.Library.V1
  """
  def context_module(%Domain{} = domain) do
    base = context_module(domain.module)

    case Domain.version_segment(domain) do
      nil -> base
      seg -> Module.concat(base, seg)
    end
  end

  def context_module(domain_module) when is_atom(domain_module) do
    parts = Module.split(domain_module)
    parts = Enum.reject(parts, &(&1 == "Domains"))
    Module.concat(parts)
  end

  @doc """
  Short context name (lowercased, underscored). Used as the table-name
  prefix and directory name. Version-agnostic: always derived from the
  raw context module so table names remain stable across versions.

      context_short(MyApp.Domains.Library) #=> "library"
  """
  def context_short(%Domain{} = domain), do: context_short(domain.module)

  def context_short(domain_module) when is_atom(domain_module) do
    domain_module
    |> context_module()
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  @doc """
  Full module name for an entity under its context. Version-aware when
  given a `Domain` struct.

      entity_module(MyApp.Domains.Library, :books)            #=> MyApp.Library.Book
      entity_module(%Domain{... version: "v1" ...}, :books)   #=> MyApp.Library.V1.Book
  """
  def entity_module(%Domain{} = domain, entity_name) do
    Module.concat(context_module(domain), camelize(singularize(entity_name)))
  end

  def entity_module(domain_module, entity_name) when is_atom(domain_module) do
    Module.concat(context_module(domain_module), camelize(singularize(entity_name)))
  end

  @doc """
  Postgres table name for an entity: `"<context>_<entity>"`. Tables are
  version-independent — different versions of a domain share a table.

      table_name(MyApp.Domains.Library, :books) #=> "library_books"
  """
  def table_name(%Domain{} = domain, entity_name), do: table_name(domain.module, entity_name)

  def table_name(domain_module, entity_name) when is_atom(domain_module) do
    context_short(domain_module) <> "_" <> to_string(entity_name)
  end

  @doc """
  File path for the generated schema module, relative to the project root.
  Version-aware when given a `Domain` struct.

      schema_file_path(MyApp.Domains.Library, :books)
      #=> "lib/my_app/library/book.ex"

      schema_file_path(%Domain{... version: "v1" ...}, :books)
      #=> "lib/my_app/library/v1/book.ex"
  """
  def schema_file_path(%Domain{} = domain, entity_name) do
    dir = context_dir(domain)
    Path.join(dir, to_string(singularize(entity_name)) <> ".ex")
  end

  def schema_file_path(domain_module, entity_name) when is_atom(domain_module) do
    dir = context_dir(domain_module)
    Path.join(dir, to_string(singularize(entity_name)) <> ".ex")
  end

  @doc """
  Association name on the parent side (plural, matches DSL entity name).

      has_many_name(:books) #=> :books
  """
  def has_many_name(entity_name), do: entity_name

  @doc """
  Association name on the child side (singular, derived).

      belongs_to_name(:authors) #=> :author
  """
  def belongs_to_name(entity_name) do
    entity_name |> singularize()
  end

  @doc """
  Foreign-key column name (`"<singular>_id"`).

      foreign_key(:authors) #=> :author_id
  """
  def foreign_key(entity_name) do
    String.to_atom(to_string(singularize(entity_name)) <> "_id")
  end

  @doc """
  Simple singularization. Handles `-ies → -y`, `-sses → -ss`, trailing `s`
  (unless preceded by another `s`). Falls back to the input unchanged.
  """
  def singularize(name) when is_atom(name),
    do: String.to_atom(singularize(Atom.to_string(name)))

  def singularize(name) when is_binary(name) do
    cond do
      String.ends_with?(name, "ies") -> String.replace_suffix(name, "ies", "y")
      String.ends_with?(name, "sses") -> String.replace_suffix(name, "sses", "ss")
      String.ends_with?(name, "ss") -> name
      String.ends_with?(name, "s") -> String.replace_suffix(name, "s", "")
      true -> name
    end
  end

  @doc "CamelCase an atom or string."
  def camelize(name) when is_atom(name), do: Macro.camelize(Atom.to_string(name))
  def camelize(name) when is_binary(name), do: Macro.camelize(name)

  @doc """
  Singular string form for a plural entity name. Used by the context
  and controller generators to derive function / route names.

      singular_string(:books) #=> "book"
  """
  def singular_string(entity_name), do: to_string(singularize(entity_name))

  @doc """
  Plural string form of an entity name.

      plural_string(:books) #=> "books"
  """
  def plural_string(entity_name), do: to_string(entity_name)

  @doc """
  File path for the generated context module, relative to the project
  root. When the domain declares a version, the context file lives under
  the context directory as `v<n>.ex`.

      context_file_path(MyApp.Domains.Library)
      #=> "lib/my_app/library.ex"

      context_file_path(%Domain{... version: "v1" ...})
      #=> "lib/my_app/library/v1.ex"
  """
  def context_file_path(%Domain{} = domain) do
    case Domain.version(domain) do
      nil ->
        context_file_path(domain.module)

      v when is_binary(v) ->
        parts =
          domain.module
          |> context_module()
          |> Module.split()
          |> Enum.map(&Macro.underscore/1)

        dir = Path.join(["lib" | parts])
        Path.join(dir, v <> ".ex")
    end
  end

  def context_file_path(domain_module) when is_atom(domain_module) do
    parts =
      domain_module
      |> context_module()
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)

    {last, dir_parts} = List.pop_at(parts, length(parts) - 1)
    dir = Path.join(["lib" | dir_parts])
    Path.join(dir, last <> ".ex")
  end

  # Directory where schema files live. With a version, adds a `v<n>/`
  # leaf dir under the context.
  defp context_dir(%Domain{} = domain) do
    base =
      domain.module
      |> context_module()
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)

    dir = Path.join(["lib" | base])

    case Domain.version(domain) do
      nil -> dir
      v -> Path.join(dir, v)
    end
  end

  defp context_dir(domain_module) when is_atom(domain_module) do
    base =
      domain_module
      |> context_module()
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)

    Path.join(["lib" | base])
  end

  @doc """
  Repo module derived by convention from the app root. `MyApp.Library`
  becomes `MyApp.Repo`.

      repo_module(MyApp.Domains.Library) #=> MyApp.Repo
  """
  def repo_module(%Domain{} = domain), do: repo_module(domain.module)

  def repo_module(domain_module) when is_atom(domain_module) do
    [root | _] = domain_module |> context_module() |> Module.split()
    Module.concat([root, "Repo"])
  end

  @doc """
  Web module name derived from the app/context root. `MyApp.Library`
  becomes `MyAppWeb`.

      web_module(MyApp.Domains.Library) #=> MyAppWeb
  """
  def web_module(%Domain{} = domain), do: web_module(domain.module)

  def web_module(domain_module) when is_atom(domain_module) do
    [root | _] = domain_module |> context_module() |> Module.split()
    Module.concat([root <> "Web"])
  end

  @doc """
  Controller module for an entity. Version-aware when given a `Domain`
  struct — inserts a version segment between the web module and the
  controller name.

      controller_module(MyApp.Domains.Library, :books)
      #=> MyAppWeb.BookController

      controller_module(%Domain{... version: "v1" ...}, :books)
      #=> MyAppWeb.V1.BookController
  """
  def controller_module(%Domain{} = domain, entity_name) do
    base =
      case Domain.version_segment(domain) do
        nil -> web_module(domain)
        seg -> Module.concat(web_module(domain), seg)
      end

    Module.concat(base, "#{camelize(singularize(entity_name))}Controller")
  end

  def controller_module(domain_module, entity_name) when is_atom(domain_module) do
    Module.concat(web_module(domain_module), "#{camelize(singularize(entity_name))}Controller")
  end

  @doc """
  Controller file path relative to the project root. Version-aware when
  given a `Domain` struct.

      controller_file_path(MyApp.Domains.Library, :books)
      #=> "lib/my_app_web/controllers/book_controller.ex"

      controller_file_path(%Domain{... version: "v1" ...}, :books)
      #=> "lib/my_app_web/controllers/v1/book_controller.ex"
  """
  def controller_file_path(%Domain{} = domain, entity_name) do
    web = web_module(domain) |> Module.split() |> List.first() |> Macro.underscore()
    filename = "#{singular_string(entity_name)}_controller.ex"

    case Domain.version(domain) do
      nil -> Path.join(["lib", web, "controllers", filename])
      v -> Path.join(["lib", web, "controllers", v, filename])
    end
  end

  def controller_file_path(domain_module, entity_name) when is_atom(domain_module) do
    web = web_module(domain_module) |> Module.split() |> List.first() |> Macro.underscore()
    Path.join(["lib", web, "controllers", "#{singular_string(entity_name)}_controller.ex"])
  end

  @doc """
  Plural route segment for an entity.

      route_path(:books) #=> "/books"
  """
  def route_path(entity_name), do: "/" <> plural_string(entity_name)

  # --- Phase 4: LiveView + Svelte naming ---------------------------------

  @doc """
  LiveView module name for an entity view. `kind` is `:index`, `:show`,
  or `:form`.

      live_module(domain, :books, :index)
      #=> MyAppWeb.Library.BookLive.Index
      #=> MyAppWeb.V1.Library.BookLive.Index  (when version set)
  """
  def live_module(%Domain{} = domain, entity_name, kind) do
    web = web_module(domain)

    web_with_version =
      case Domain.version_segment(domain) do
        nil -> web
        seg -> Module.concat(web, seg)
      end

    ctx_short = domain |> context_short() |> Macro.camelize()
    entity_camel = camelize(singularize(entity_name))
    kind_camel = kind |> Atom.to_string() |> Macro.camelize()

    Module.concat([web_with_version, ctx_short, entity_camel <> "Live", kind_camel])
  end

  @doc """
  File path for a generated LiveView module.

      live_file_path(domain, :books, :index)
      #=> "lib/my_app_web/live/library/book_live/index.ex"
      #=> "lib/my_app_web/live/v1/library/book_live/index.ex"  (when versioned)
  """
  def live_file_path(%Domain{} = domain, entity_name, kind) do
    web_root = web_module(domain) |> Module.split() |> List.first() |> Macro.underscore()
    ctx_short = context_short(domain)
    entity = singular_string(entity_name)
    kind_s = Atom.to_string(kind)

    base_segments =
      case Domain.version(domain) do
        nil -> ["lib", web_root, "live", ctx_short]
        v -> ["lib", web_root, "live", v, ctx_short]
      end

    Path.join(base_segments ++ ["#{entity}_live", "#{kind_s}.ex"])
  end

  @doc """
  Svelte component name (CamelCase). `kind` is `:index`, `:show`, or
  `:form`.

      svelte_component_name(:books, :index) #=> "BookIndex"
      svelte_component_name(:books, :form)  #=> "BookForm"
  """
  def svelte_component_name(entity_name, kind) do
    camelize(singularize(entity_name)) <> Macro.camelize(Atom.to_string(kind))
  end

  @doc """
  LiveSvelte component reference — the path string passed to
  `<LiveSvelte.render name="..." />`. Matches the Svelte-file path
  relative to `assets/svelte/`, without the `.svelte` extension.

      svelte_component_ref(domain, :books, :index) #=> "library/BookIndex"
      #=> "v1/library/BookIndex"                   (when versioned)
  """
  def svelte_component_ref(%Domain{} = domain, entity_name, kind) do
    component = svelte_component_name(entity_name, kind)
    ctx_short = context_short(domain)

    case Domain.version(domain) do
      nil -> "#{ctx_short}/#{component}"
      v -> "#{v}/#{ctx_short}/#{component}"
    end
  end

  @doc """
  Filesystem path for the generated Svelte component.

      svelte_file_path(domain, :books, :index)
      #=> "assets/svelte/library/BookIndex.svelte"
      #=> "assets/svelte/v1/library/BookIndex.svelte"  (when versioned)
  """
  def svelte_file_path(%Domain{} = domain, entity_name, kind) do
    component = svelte_component_name(entity_name, kind)
    ctx_short = context_short(domain)

    segments =
      case Domain.version(domain) do
        nil -> ["assets", "svelte", ctx_short]
        v -> ["assets", "svelte", v, ctx_short]
      end

    Path.join(segments ++ ["#{component}.svelte"])
  end

  @doc """
  Filesystem path for the generated TypeScript interfaces file.

      svelte_types_file_path(domain)
      #=> "assets/svelte/types/library.ts"
      #=> "assets/svelte/v1/types/library.ts"  (when versioned)
  """
  def svelte_types_file_path(%Domain{} = domain) do
    ctx_short = context_short(domain)

    segments =
      case Domain.version(domain) do
        nil -> ["assets", "svelte", "types"]
        v -> ["assets", "svelte", v, "types"]
      end

    Path.join(segments ++ ["#{ctx_short}.ts"])
  end
end
