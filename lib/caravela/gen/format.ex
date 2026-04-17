defmodule Caravela.Gen.Format do
  @moduledoc false

  # Mirrors the `locals_without_parens` that ecto_sql exposes via its
  # own .formatter.exs, so generated migrations and schemas format
  # cleanly even when Code.format_string!/2 is invoked without access
  # to the consumer project's formatter config.
  @locals_without_parens [
    # Ecto.Schema
    field: 1,
    field: 2,
    field: 3,
    belongs_to: 2,
    belongs_to: 3,
    has_many: 2,
    has_many: 3,
    has_one: 2,
    has_one: 3,
    many_to_many: 2,
    many_to_many: 3,
    embeds_one: 2,
    embeds_one: 3,
    embeds_one: 4,
    embeds_many: 2,
    embeds_many: 3,
    embeds_many: 4,
    timestamps: 0,
    timestamps: 1,

    # Ecto.Changeset
    cast: 2,
    cast: 3,
    cast: 4,
    validate_required: 1,
    validate_required: 2,
    validate_length: 2,
    validate_format: 2,
    validate_number: 2,
    validate_inclusion: 2,
    foreign_key_constraint: 1,
    foreign_key_constraint: 2,

    # Ecto.Migration
    add: 2,
    add: 3,
    add_if_not_exists: 2,
    add_if_not_exists: 3,
    alter: 1,
    constraint: 2,
    constraint: 3,
    create: 1,
    create: 2,
    create_if_not_exists: 1,
    create_if_not_exists: 2,
    drop: 1,
    drop: 2,
    drop_if_exists: 1,
    drop_if_exists: 2,
    execute: 1,
    execute: 2,
    flush: 0,
    modify: 2,
    modify: 3,
    references: 1,
    references: 2,
    remove: 1,
    remove: 2,
    remove: 3,
    remove_if_exists: 1,
    remove_if_exists: 2,
    rename: 2,
    rename: 3,
    reverse: 0,
    table: 1,
    table: 2
  ]

  @doc "Formats Elixir source like `mix format` would in an ecto_sql project."
  def format!(source) do
    source
    |> Code.format_string!(locals_without_parens: @locals_without_parens)
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  @doc "Same as `format!/1` but returns the unformatted source on failure."
  def try_format(source) do
    try do
      format!(source)
    rescue
      _ -> source
    end
  end
end
