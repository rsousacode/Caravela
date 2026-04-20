defmodule Caravela.Gen.Migration do
  @moduledoc """
  Generates a single Ecto migration file for every entity in a
  `Caravela.Schema.Domain`.

  Returns `{path, source}` - the caller writes the file. The migration
  file name is timestamped so subsequent runs produce a distinct file.

  ## Deterministic output

  By default the migration's filename prefix is `now()` in UTC. For
  snapshot tests, demos, or any scenario where you want byte-stable
  output across runs, pass `:timestamp`:

      Caravela.Gen.Migration.render(domain, timestamp: "00000000000000")

  Without this pin, every render produces a new path and snapshot diffs
  always appear as "add + remove".
  """

  alias Caravela.Schema.Domain
  alias Caravela.{Naming, Types}

  @template_path Path.expand("../../../priv/templates/migration.eex", __DIR__)

  @doc """
  Render the migration for the domain.

  Options:
    * `:timestamp` - override the numeric prefix (defaults to `now()`)
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

  @doc """
  Locate an existing migration file for the domain's create-tables
  step, relative to `root`.

  Returns the file's basename (e.g.
  `"20260417094708_create_library_tables.exs"`) when a prior
  migration with the same stem exists, or `nil` when none does.
  Reuse its 14-digit timestamp prefix to overwrite the same file on
  regeneration instead of appending a duplicate (see
  `reconcile_timestamp/2`).

  When more than one matching migration is present (a symptom of
  prior regenerations that didn't reconcile), the *oldest* one is
  returned - regenerating against it lets the caller consolidate
  state while still surfacing the duplicates for manual cleanup.
  """
  @spec existing_migration_basename(Domain.t(), Path.t()) :: String.t() | nil
  def existing_migration_basename(%Domain{} = domain, root) do
    ctx_short = Naming.context_short(domain.module)
    dir = Path.join(root, "priv/repo/migrations")

    if File.dir?(dir) do
      ~r/^\d{14}_create_#{Regex.escape(ctx_short)}_tables\.exs$/
      |> match_in(dir)
      |> Enum.sort()
      |> List.first()
    end
  end

  @doc """
  Decide which timestamp `render/2` should use given the current
  filesystem state:

    * No matching migration on disk → `default_timestamp/0`.
    * Exactly one matching migration → reuse its timestamp, so
      `render/2` produces the same path (idempotent regeneration).
    * More than one matching migration → reuse the *oldest*
      timestamp and return the extras so the caller can warn
      about the drift.

  Returns `{timestamp, duplicates}` where `duplicates` is a list of
  basenames callers should flag or clean up.
  """
  @spec reconcile_timestamp(Domain.t(), Path.t()) :: {String.t(), [String.t()]}
  def reconcile_timestamp(%Domain{} = domain, root) do
    ctx_short = Naming.context_short(domain.module)
    dir = Path.join(root, "priv/repo/migrations")

    matching =
      if File.dir?(dir) do
        ~r/^(?<ts>\d{14})_create_#{Regex.escape(ctx_short)}_tables\.exs$/
        |> match_in(dir)
        |> Enum.sort()
      else
        []
      end

    case matching do
      [] ->
        {default_timestamp(), []}

      [sole] ->
        {timestamp_from(sole), []}

      [primary | rest] ->
        {timestamp_from(primary), rest}
    end
  end

  defp match_in(regex, dir) do
    dir
    |> File.ls!()
    |> Enum.filter(&Regex.match?(regex, &1))
  end

  defp timestamp_from(basename) do
    basename |> String.split("_", parts: 2) |> List.first()
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
        # Cycle in non-required belongs_to - fall back to declaration order.
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
