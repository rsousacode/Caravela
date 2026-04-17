defmodule Caravela.DomainTest do
  use ExUnit.Case, async: true

  describe "valid domain" do
    defmodule Library do
      use Caravela.Domain

      entity :authors do
        field :name, :string, required: true
        field :bio, :text
        field :born, :date
      end

      entity :books do
        field :title, :string, required: true, min_length: 3
        field :isbn, :string, format: ~r/^\d{13}$/
        field :published, :boolean, default: false
        field :price, :decimal, precision: 10, scale: 2
      end

      entity :publishers do
        field :name, :string, required: true
        field :country, :string
      end

      relation :authors, :books, type: :has_many
      relation :books, :publishers, type: :belongs_to
    end

    test "exposes the compiled IR via __caravela_domain__/0" do
      domain = Library.__caravela_domain__()
      assert domain.module == Library
      assert length(domain.entities) == 3
      assert length(domain.relations) == 2
    end

    test "preserves field order within an entity" do
      domain = Library.__caravela_domain__()
      books = Enum.find(domain.entities, &(&1.name == :books))
      assert Enum.map(books.fields, & &1.name) == [:title, :isbn, :published, :price]
    end

    test "preserves field options including regex, default, precision" do
      domain = Library.__caravela_domain__()
      books = Enum.find(domain.entities, &(&1.name == :books))
      isbn = Enum.find(books.fields, &(&1.name == :isbn))
      assert Regex.source(Keyword.fetch!(isbn.opts, :format)) == "^\\d{13}$"

      published = Enum.find(books.fields, &(&1.name == :published))
      assert Keyword.fetch!(published.opts, :default) == false

      price = Enum.find(books.fields, &(&1.name == :price))
      assert Keyword.fetch!(price.opts, :precision) == 10
    end
  end

  describe "validation failures" do
    test "unknown field type is rejected" do
      assert_raise CompileError, ~r/unknown field type :widget/, fn ->
        defmodule BadType do
          use Caravela.Domain

          entity :gadgets do
            field :size, :widget
          end
        end
      end
    end

    test "relation to undefined entity is rejected" do
      assert_raise CompileError, ~r/unknown entity :ghost/, fn ->
        defmodule BadRelation do
          use Caravela.Domain

          entity :things do
            field :name, :string
          end

          relation :things, :ghost, type: :has_many
        end
      end
    end

    test "invalid relation type is rejected" do
      assert_raise CompileError, ~r/invalid relation type :vibes/, fn ->
        defmodule BadRelType do
          use Caravela.Domain

          entity :a do
            field :n, :string
          end

          entity :b do
            field :n, :string
          end

          relation :a, :b, type: :vibes
        end
      end
    end

    test "numeric constraint on non-numeric field is rejected" do
      assert_raise CompileError, ~r/numeric option :min/, fn ->
        defmodule BadConstraint do
          use Caravela.Domain

          entity :things do
            field :name, :string, min: 1
          end
        end
      end
    end

    test "string constraint on non-string field is rejected" do
      assert_raise CompileError, ~r/string option :min_length/, fn ->
        defmodule BadStringConstraint do
          use Caravela.Domain

          entity :things do
            field :count, :integer, min_length: 1
          end
        end
      end
    end

    test "duplicate entity is rejected" do
      assert_raise CompileError, ~r/duplicate entity :things/, fn ->
        defmodule DupEntity do
          use Caravela.Domain

          entity :things do
            field :name, :string
          end

          entity :things do
            field :name, :string
          end
        end
      end
    end

    test "incompatible cardinality between declared sides is rejected" do
      assert_raise CompileError, ~r/incompatible cardinality/, fn ->
        defmodule BadCardinality do
          use Caravela.Domain

          entity :a do
            field :n, :string
          end

          entity :b do
            field :n, :string
          end

          relation :a, :b, type: :has_many
          relation :b, :a, type: :has_many
        end
      end
    end

    test "circular required belongs_to chain (3-cycle) is rejected" do
      assert_raise CompileError, ~r/circular required belongs_to/, fn ->
        defmodule Cycle do
          use Caravela.Domain

          entity :a do
            field :n, :string
          end

          entity :b do
            field :n, :string
          end

          entity :c do
            field :n, :string
          end

          relation :a, :b, type: :belongs_to, required: true
          relation :b, :c, type: :belongs_to, required: true
          relation :c, :a, type: :belongs_to, required: true
        end
      end
    end

    test "non-required belongs_to cycle (3-cycle) is allowed" do
      defmodule SoftCycle do
        use Caravela.Domain

        entity :a do
          field :n, :string
        end

        entity :b do
          field :n, :string
        end

        entity :c do
          field :n, :string
        end

        relation :a, :b, type: :belongs_to
        relation :b, :c, type: :belongs_to
        relation :c, :a, type: :belongs_to
      end

      assert %Caravela.Schema.Domain{} = SoftCycle.__caravela_domain__()
    end
  end
end
