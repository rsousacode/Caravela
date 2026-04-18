defmodule Caravela.Gen.EctoSchema do
  @moduledoc """
  Generates one Ecto schema module per entity from a compiled
  `Caravela.Schema.Domain`.

  Returns a list of `{path, source}` tuples. `Caravela.Gen` or the Mix
  task is responsible for actually writing the files. Files preserve
  content below the `# --- CUSTOM ---` marker on regeneration.
  """

  alias Caravela.Schema.{AuthConfig, Domain}
  alias Caravela.{Auth, Gen, Naming}

  @template_path Path.expand("../../../priv/templates/ecto_schema.eex", __DIR__)

  @doc "Render every entity in the domain as an Ecto schema file."
  def render_all(%Domain{} = domain, opts \\ []) do
    Enum.map(domain.entities, fn entity ->
      path = Naming.schema_file_path(domain, entity.name)
      source = render_entity(domain, entity, opts)
      {path, source}
    end)
  end

  @doc "Render a single entity."
  def render_entity(%Domain{} = domain, entity, opts \\ []) do
    root = Keyword.get(opts, :root, File.cwd!())
    path = Naming.schema_file_path(domain, entity.name)
    existing_path = Path.join(root, path)

    assigns = build_assigns(domain, entity)
    rendered = EEx.eval_file(@template_path, assigns: assigns, trim: true)

    rendered
    |> Gen.Custom.merge_with_file(existing_path)
    |> Caravela.Gen.Format.try_format()
  end

  # --- Assigns -----------------------------------------------------------

  defp build_assigns(domain, entity) do
    assocs = collect_associations(domain, entity)

    has_many = assocs |> Enum.filter(&(&1.kind == :has_many)) |> Enum.uniq_by(& &1.assoc_name)
    has_one = assocs |> Enum.filter(&(&1.kind == :has_one)) |> Enum.uniq_by(& &1.assoc_name)
    belongs_to = assocs |> Enum.filter(&(&1.kind == :belongs_to)) |> Enum.uniq_by(& &1.assoc_name)

    # Tenant- and auth-injected fields are declared on the schema but
    # kept out of the generic changeset cast. Tenant id is stamped by
    # the context; auth fields flow through specialised changesets
    # (`registration_changeset`, `password_changeset`, …).
    castable_fields =
      entity.fields
      |> Enum.reject(&Caravela.Tenant.injected?/1)
      |> Enum.reject(&Auth.injected?/1)

    required_plain =
      for f <- castable_fields, Keyword.get(f.opts || [], :required, false), do: f.name

    optional_plain =
      for f <- castable_fields, not Keyword.get(f.opts || [], :required, false), do: f.name

    optional_fks = Enum.map(belongs_to, & &1.fk)

    auth_cfg = entity.auth

    [
      module: Naming.entity_module(domain, entity.name),
      domain_module: domain.module,
      table: Naming.table_name(domain, entity.name),
      plain_fields: entity.fields,
      has_many: has_many,
      has_one: has_one,
      belongs_to: belongs_to,
      required_fields: required_plain,
      optional_fields: optional_plain ++ optional_fks,
      validation_lines: build_validations(castable_fields),
      auth: auth_cfg,
      auth_password?: match?(%AuthConfig{}, auth_cfg) and AuthConfig.password?(auth_cfg),
      auth_confirm?: match?(%AuthConfig{}, auth_cfg) and AuthConfig.confirm?(auth_cfg),
      auth_api_token?: match?(%AuthConfig{}, auth_cfg) and AuthConfig.api_token?(auth_cfg),
      custom_marker: Gen.Custom.marker_block()
    ]
  end

  # --- Relation assembly -------------------------------------------------

  defp collect_associations(domain, entity) do
    Enum.flat_map(domain.relations, fn rel ->
      cond do
        rel.from == entity.name -> [assoc_from_declared(rel, domain)]
        rel.to == entity.name -> [assoc_from_inferred(rel, domain)]
        true -> []
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp assoc_from_declared(rel, domain) do
    case rel.type do
      :has_many ->
        %{
          kind: :has_many,
          assoc_name: Naming.has_many_name(rel.to),
          target_module: Naming.entity_module(domain, rel.to)
        }

      :has_one ->
        %{
          kind: :has_one,
          assoc_name: Naming.belongs_to_name(rel.to),
          target_module: Naming.entity_module(domain, rel.to)
        }

      :belongs_to ->
        %{
          kind: :belongs_to,
          assoc_name: Naming.belongs_to_name(rel.to),
          target_module: Naming.entity_module(domain, rel.to),
          fk: Naming.foreign_key(rel.to)
        }

      :many_to_many ->
        nil
    end
  end

  defp assoc_from_inferred(rel, domain) do
    case rel.type do
      :has_many ->
        %{
          kind: :belongs_to,
          assoc_name: Naming.belongs_to_name(rel.from),
          target_module: Naming.entity_module(domain, rel.from),
          fk: Naming.foreign_key(rel.from)
        }

      :has_one ->
        %{
          kind: :belongs_to,
          assoc_name: Naming.belongs_to_name(rel.from),
          target_module: Naming.entity_module(domain, rel.from),
          fk: Naming.foreign_key(rel.from)
        }

      :belongs_to ->
        %{
          kind: :has_many,
          assoc_name: Naming.has_many_name(rel.from),
          target_module: Naming.entity_module(domain, rel.from)
        }

      :many_to_many ->
        nil
    end
  end

  # --- Validation line assembly ------------------------------------------

  defp build_validations(fields) do
    Enum.flat_map(fields, fn f ->
      opts = f.opts || []
      name = f.name

      length_opts =
        [min: Keyword.get(opts, :min_length), max: Keyword.get(opts, :max_length)]
        |> Enum.reject(fn {_, v} -> is_nil(v) end)

      number_opts =
        [
          greater_than_or_equal_to: Keyword.get(opts, :min),
          less_than_or_equal_to: Keyword.get(opts, :max)
        ]
        |> Enum.reject(fn {_, v} -> is_nil(v) end)

      format = Keyword.get(opts, :format)

      lines = []

      lines =
        if length_opts == [],
          do: lines,
          else: ["validate_length(:#{name}, #{fmt_kw(length_opts)})" | lines]

      lines =
        if number_opts == [],
          do: lines,
          else: ["validate_number(:#{name}, #{fmt_kw(number_opts)})" | lines]

      lines =
        if is_nil(format),
          do: lines,
          else: ["validate_format(:#{name}, #{inspect(format)})" | lines]

      Enum.map(Enum.reverse(lines), &{&1, f})
    end)
  end

  defp fmt_kw(pairs) do
    Enum.map_join(pairs, ", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
  end
end
