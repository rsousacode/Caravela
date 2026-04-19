defmodule Caravela.Types do
  @moduledoc """
  Type mapping between the Caravela DSL, Ecto, and Postgres.

  The DSL uses plain atoms like `:string`, `:integer`, `:decimal`, `:text`.
  Those are translated into Ecto field types (for schema generation) and
  Postgres column types (for migration generation).
  """

  @mappings %{
    string: {:string, :string},
    text: {:string, :text},
    integer: {:integer, :integer},
    bigint: {:integer, :bigint},
    float: {:float, :float},
    decimal: {:decimal, :decimal},
    boolean: {:boolean, :boolean},
    date: {:date, :date},
    time: {:time, :time},
    naive_datetime: {:naive_datetime, :naive_datetime},
    utc_datetime: {:utc_datetime, :utc_datetime},
    binary: {:binary, :binary},
    binary_id: {:binary_id, :uuid},
    uuid: {:binary_id, :uuid},
    map: {:map, :map},
    json: {:map, :jsonb},
    jsonb: {:map, :jsonb}
  }

  @numeric_types ~w(integer bigint float decimal)a
  @string_types ~w(string text binary)a

  @typedoc "A DSL type atom recognised by Caravela."
  @type dsl_type :: atom()

  @doc "All DSL types recognised by Caravela."
  @spec known_types() :: [dsl_type()]
  def known_types, do: Map.keys(@mappings)

  @doc "Is the atom a known DSL type?"
  @spec known?(dsl_type()) :: boolean()
  def known?(type), do: Map.has_key?(@mappings, type)

  @doc "Ecto type for a DSL atom. Raises if unknown."
  @spec ecto_type(dsl_type()) :: atom()
  def ecto_type(type) do
    case @mappings do
      %{^type => {ecto, _}} -> ecto
      _ -> raise Caravela.DSLError, unknown_type_error(type)
    end
  end

  @doc "Postgres column type for a DSL atom. Raises if unknown."
  @spec postgres_type(dsl_type()) :: atom()
  def postgres_type(type) do
    case @mappings do
      %{^type => {_, pg}} -> pg
      _ -> raise Caravela.DSLError, unknown_type_error(type)
    end
  end

  defp unknown_type_error(type) do
    [
      message: "unknown Caravela field type: #{inspect(type)}",
      suggestion: "Supported types: #{Enum.map_join(known_types(), ", ", &inspect/1)}",
      docs_url: "https://hexdocs.pm/caravela/dsl.html#field-types"
    ]
  end

  @doc "True for numeric DSL types."
  @spec numeric?(dsl_type()) :: boolean()
  def numeric?(type), do: type in @numeric_types

  @doc "True for string-ish DSL types."
  @spec string_like?(dsl_type()) :: boolean()
  def string_like?(type), do: type in @string_types
end
