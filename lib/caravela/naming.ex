defmodule Caravela.Naming do
  @moduledoc """
  Naming conventions translating domain declarations into Elixir module
  names, file paths, and Postgres table names.

  The DSL uses plural entity names (`entity :books`). The generator
  translates them into singular module names (`Book`), plural table names
  (`library_books`), and the matching file paths under `lib/`.

  The domain module's `.Domains.` segment (if present) is stripped to
  obtain the "context module": `MyApp.Domains.Library` → `MyApp.Library`.
  """

  @doc """
  Context module derived from the domain module by stripping a `.Domains.`
  segment if present.

      context_module(MyApp.Domains.Library) #=> MyApp.Library
      context_module(MyApp.Library)         #=> MyApp.Library
  """
  def context_module(domain_module) do
    parts = Module.split(domain_module)
    parts = Enum.reject(parts, &(&1 == "Domains"))
    Module.concat(parts)
  end

  @doc """
  Short context name (lowercased, underscored). Used as the table-name
  prefix and directory name.

      context_short(MyApp.Domains.Library) #=> "library"
  """
  def context_short(domain_module) do
    domain_module
    |> context_module()
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  @doc """
  Full module name for an entity under its context.

      entity_module(MyApp.Domains.Library, :books) #=> MyApp.Library.Book
  """
  def entity_module(domain_module, entity_name) do
    ctx = context_module(domain_module)
    Module.concat(ctx, camelize(singularize(entity_name)))
  end

  @doc """
  Postgres table name for an entity: `"<context>_<entity>"`.

      table_name(MyApp.Domains.Library, :books) #=> "library_books"
  """
  def table_name(domain_module, entity_name) do
    context_short(domain_module) <> "_" <> to_string(entity_name)
  end

  @doc """
  File path for the generated schema module, relative to the project root.

      schema_file_path(MyApp.Domains.Library, :books)
      #=> "lib/my_app/library/book.ex"
  """
  def schema_file_path(domain_module, entity_name) do
    ctx_parts =
      domain_module
      |> context_module()
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)

    dir = Path.join(["lib" | ctx_parts])
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
end
