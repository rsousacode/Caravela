defmodule Caravela.Gen.Migration do
  @moduledoc """
  Generates a single Ecto migration file for every entity in a
  `Caravela.Schema.Domain`.

  Returns `{path, source}` — the caller writes the file. The migration
  file name is timestamped so subsequent runs produce a distinct file.
  """

  alias Caravela.Schema.Domain
  alias Caravela.{Naming, Types}

  @template_path Path.expand("../../../priv/templates/migration.eex", __DIR__)

  @doc """
  Render the migration for the domain.

  Options:
    * `:timestamp` — override the numeric prefix (defaults to `now()`)
  """
  def render(%Domain{} = domain, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, default_timestamp())
    ctx_short = Naming.context_short(domain.module)
    module_name = Module.concat(["Caravela.Migrations", Naming.camelize(ctx_short), "Create"])

    assigns = [
      module: module_name,
      tables: build_tables(domain)
    ]

    source =
      EEx.eval_file(@template_path, assigns: assigns, trim: true)
      |> Caravela.Gen.Format.try_format()

    path = Path.join("priv/repo/migrations", "#{timestamp}_create_#{ctx_short}_tables.exs")
    {path, source}
  end

  defp default_timestamp do
    {{y, mo, d}, {h, mi, s}} = :calendar.universal_time()

    :io_lib.format("~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B", [y, mo, d, h, mi, s])
    |> IO.iodata_to_binary()
  end

  # --- Build per-table data in creation order ---------------------------

  defp build_tables(%Domain{} = domain) do
    ordered = topological_order(domain)
    tenant? = Domain.multi_tenant?(domain)

    Enum.map(ordered, fn entity ->
      belongs_to_rels = belongs_to_for_entity(domain, entity)

      fk_indexes =
        belongs_to_rels
        |> Enum.map(fn {other_entity, _required?} -> Naming.foreign_key(other_entity) end)
        |> Enum.uniq()

      # When multi-tenant, add composite indexes (`[:tenant_id, :<fk>]`)
      # in addition to the FK indexes so tenant-scoped queries on related
      # entities remain fast. Also add a standalone `[:tenant_id]` index
      # when the table has no FKs at all.
      composite_indexes =
        if tenant? and fk_indexes != [] do
          Enum.map(fk_indexes, fn fk -> [:tenant_id, fk] end)
        else
          []
        end

      single_tenant_index =
        if tenant? and fk_indexes == [], do: [[:tenant_id]], else: []

      %{
        name: Naming.table_name(domain, entity.name),
        columns: build_columns(entity),
        refs: build_refs(domain, belongs_to_rels),
        indexes: Enum.map(fk_indexes, &[&1]) ++ composite_indexes ++ single_tenant_index
      }
    end)
  end

  defp build_columns(entity) do
    Enum.map(entity.fields, fn f ->
      opts = f.opts || []

      %{
        name: f.name,
        pg_type: Types.postgres_type(f.type),
        null: not Keyword.get(opts, :required, false),
        default: Keyword.get(opts, :default, :__no_default__),
        precision: Keyword.get(opts, :precision),
        scale: Keyword.get(opts, :scale)
      }
    end)
  end

  defp build_refs(domain, belongs_to_rels) do
    Enum.map(belongs_to_rels, fn {other_entity, required?} ->
      %{
        column: Naming.foreign_key(other_entity),
        table: Naming.table_name(domain, other_entity),
        on_delete: if(required?, do: :delete_all, else: :nilify_all),
        null: not required?
      }
    end)
    |> Enum.uniq_by(& &1.column)
  end

  # Returns list of {other_entity, required?} pairs describing every
  # belongs_to that this entity has (declared or inferred).
  defp belongs_to_for_entity(domain, entity) do
    Enum.flat_map(domain.relations, fn rel ->
      required? = Keyword.get(rel.opts || [], :required, false)

      cond do
        rel.from == entity.name and rel.type == :belongs_to ->
          [{rel.to, required?}]

        rel.to == entity.name and rel.type in [:has_many, :has_one] ->
          [{rel.from, required?}]

        true ->
          []
      end
    end)
    |> Enum.uniq_by(fn {e, _} -> e end)
  end

  # --- Topological sort so referenced tables are created first ----------

  defp topological_order(%Domain{entities: entities} = domain) do
    deps =
      Map.new(entities, fn e ->
        target_entities =
          belongs_to_for_entity(domain, e)
          |> Enum.map(fn {other, _} -> other end)

        {e.name, target_entities}
      end)

    order = kahn(deps)

    Enum.map(order, fn name -> Enum.find(entities, &(&1.name == name)) end)
  end

  defp kahn(deps) when map_size(deps) == 0, do: []

  defp kahn(deps) do
    case Enum.find(deps, fn {_, d} -> d == [] end) do
      nil ->
        # Cycle in non-required belongs_to — fall back to declaration order.
        Map.keys(deps)

      {node, _} ->
        rest =
          deps
          |> Map.delete(node)
          |> Map.new(fn {k, v} -> {k, v -- [node]} end)

        [node | kahn(rest)]
    end
  end
end
