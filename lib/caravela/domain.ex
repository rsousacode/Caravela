defmodule Caravela.Domain do
  @moduledoc """
  DSL entry point. `use Caravela.Domain` in a module to declare a domain:

      defmodule MyApp.Domains.Library do
        use Caravela.Domain

        entity :authors do
          field :name, :string, required: true
          field :bio, :text
        end

        entity :books do
          field :title, :string, required: true, min_length: 3
          field :isbn, :string, format: ~r/^\\d{13}$/
        end

        relation :authors, :books, type: :has_many
      end

  After compilation the module exposes `__caravela_domain__/0`, returning
  the validated `Caravela.Schema.Domain` IR.
  """

  defmacro __using__(opts) do
    quote do
      import Caravela.Domain, only: [entity: 2, field: 2, field: 3, relation: 3]

      Module.register_attribute(__MODULE__, :caravela_entities, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_relations, accumulate: true)
      Module.register_attribute(__MODULE__, :caravela_domain_opts, persist: false)
      Module.register_attribute(__MODULE__, :caravela_current_fields, persist: false)

      @caravela_domain_opts unquote(opts)
      @before_compile Caravela.Compiler
    end
  end

  @doc """
  Declare an entity (a table/schema) with a `do` block of fields.

      entity :books do
        field :title, :string, required: true
      end
  """
  defmacro entity(name, do: block) do
    quote do
      @caravela_current_fields []
      unquote(block)
      fields = Enum.reverse(Module.get_attribute(__MODULE__, :caravela_current_fields))

      @caravela_entities %Caravela.Schema.Entity{
        name: unquote(name),
        fields: fields
      }

      Module.delete_attribute(__MODULE__, :caravela_current_fields)
    end
  end

  @doc """
  Declare a field inside an `entity` block.

      field :title, :string, required: true, min_length: 3
  """
  defmacro field(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      unless is_atom(name), do: raise(ArgumentError, "field name must be an atom")
      unless is_atom(type), do: raise(ArgumentError, "field type must be an atom")

      entry = %Caravela.Schema.Field{name: name, type: type, opts: opts}
      current = Module.get_attribute(__MODULE__, :caravela_current_fields) || []
      Module.put_attribute(__MODULE__, :caravela_current_fields, [entry | current])
    end
  end

  @doc """
  Declare a relation between two entities.

      relation :authors, :books, type: :has_many
      relation :books, :publishers, type: :belongs_to
  """
  defmacro relation(from, to, opts) do
    quote bind_quoted: [from: from, to: to, opts: opts] do
      type = Keyword.fetch!(opts, :type)
      other = Keyword.delete(opts, :type)

      @caravela_relations %Caravela.Schema.Relation{
        from: from,
        to: to,
        type: type,
        opts: other
      }
    end
  end
end
