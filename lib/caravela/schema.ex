defmodule Caravela.Schema do
  @moduledoc """
  Internal Intermediate Representation (IR) for a Caravela domain.

  Parsed from the `Caravela.Domain` DSL at compile time, validated by
  `Caravela.Compiler`, and consumed by the code generators in
  `Caravela.Gen.*`.
  """

  defmodule Field do
    @moduledoc "A single field on an entity."
    defstruct [:name, :type, :opts]

    @type t :: %__MODULE__{
            name: atom(),
            type: atom(),
            opts: keyword()
          }
  end

  defmodule Entity do
    @moduledoc "A domain entity (table)."
    defstruct [:name, fields: []]

    @type t :: %__MODULE__{
            name: atom(),
            fields: [Field.t()]
          }
  end

  defmodule Relation do
    @moduledoc """
    A relation between two entities.

    * `from` is the owning entity as declared in the DSL.
    * `to` is the related entity as declared.
    * `type` is one of `:has_many`, `:has_one`, `:belongs_to`, `:many_to_many`.
    """
    defstruct [:from, :to, :type, opts: []]

    @type t :: %__MODULE__{
            from: atom(),
            to: atom(),
            type: :has_many | :has_one | :belongs_to | :many_to_many,
            opts: keyword()
          }
  end

  defmodule Domain do
    @moduledoc "A whole domain: the top-level IR produced by compilation."
    defstruct [:module, entities: [], relations: [], opts: []]

    @type t :: %__MODULE__{
            module: module(),
            entities: [Entity.t()],
            relations: [Relation.t()],
            opts: keyword()
          }

    @doc "Lookup an entity by its DSL name."
    def fetch_entity(%__MODULE__{entities: es}, name) do
      Enum.find(es, &(&1.name == name))
    end
  end
end
