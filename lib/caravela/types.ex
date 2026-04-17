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

  @doc "All DSL types recognised by Caravela."
  def known_types, do: Map.keys(@mappings)

  @doc "Is the atom a known DSL type?"
  def known?(type), do: Map.has_key?(@mappings, type)

  @doc "Ecto type for a DSL atom. Raises if unknown."
  def ecto_type(type) do
    case @mappings do
      %{^type => {ecto, _}} -> ecto
      _ -> raise ArgumentError, "unknown Caravela field type: #{inspect(type)}"
    end
  end

  @doc "Postgres column type for a DSL atom. Raises if unknown."
  def postgres_type(type) do
    case @mappings do
      %{^type => {_, pg}} -> pg
      _ -> raise ArgumentError, "unknown Caravela field type: #{inspect(type)}"
    end
  end

  @doc "True for numeric DSL types."
  def numeric?(type), do: type in @numeric_types

  @doc "True for string-ish DSL types."
  def string_like?(type), do: type in @string_types
end
