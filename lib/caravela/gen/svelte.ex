defmodule Caravela.Gen.Svelte do
  @moduledoc """
  Generates typed Svelte components and a TypeScript interfaces file
  from a `Caravela.Schema.Domain`.

  Output per entity:

    * `BookIndex.svelte` — list view
    * `BookShow.svelte` — detail view
    * `BookForm.svelte` — create/edit form

  Plus one TypeScript file per domain holding every entity's interface.
  File paths mirror the context and version namespaces (see
  `Caravela.Naming.svelte_file_path/3` and
  `Caravela.Naming.svelte_types_file_path/1`).

  Tenant-injected fields are hidden from both the TypeScript interface
  and the form inputs — tenant id comes from the server, not the
  Svelte client.

  Returns a list of `{path, source}` tuples. Files preserve content
  below the `# --- CUSTOM ---` / `<!-- --- CUSTOM --- -->` marker on
  regeneration.
  """

  alias Caravela.Schema.{Domain, Entity, Field}
  alias Caravela.{Naming, Tenant}

  @types_template Path.expand("../../../priv/templates/svelte_types.eex", __DIR__)
  @index_template Path.expand("../../../priv/templates/svelte_index.eex", __DIR__)
  @show_template Path.expand("../../../priv/templates/svelte_show.eex", __DIR__)
  @form_template Path.expand("../../../priv/templates/svelte_form.eex", __DIR__)

  @doc "Render types + every component for every entity."
  def render_all(%Domain{} = domain, opts \\ []) do
    [render_types(domain, opts) | render_components(domain, opts)]
  end

  @doc "Render only the TypeScript interfaces file."
  def render_types(%Domain{} = domain, opts \\ []) do
    path = Naming.svelte_types_file_path(domain)
    existing = existing_path(path, opts)

    auth_entity = Domain.auth_entity(domain)

    assigns = [
      domain_module: inspect(domain.module),
      entities: Enum.map(domain.entities, &ts_entity_assign/1),
      authenticated: not is_nil(auth_entity),
      user_ts_name: auth_user_ts_name(auth_entity),
      api_token_scopes: auth_token_scopes_ts(auth_entity)
    ]

    source =
      EEx.eval_file(@types_template, assigns: assigns, trim: true)
      |> merge_ts(existing)

    {path, source}
  end

  defp auth_user_ts_name(nil), do: nil

  defp auth_user_ts_name(%Entity{name: name}),
    do: Naming.camelize(Naming.singularize(name))

  defp auth_token_scopes_ts(nil), do: nil

  defp auth_token_scopes_ts(%Entity{auth: cfg}) do
    case Caravela.Schema.AuthConfig.strategy_opts(cfg, :api_token) do
      nil ->
        nil

      opts ->
        opts
        |> Keyword.get(:scopes, [:read, :write])
        |> Enum.map(&("'" <> Atom.to_string(&1) <> "'"))
        |> Enum.join(" | ")
    end
  end

  @doc "Render every Svelte component (index, show, form) for every entity."
  def render_components(%Domain{} = domain, opts \\ []) do
    Enum.flat_map(domain.entities, fn entity ->
      [
        render_component(domain, entity, :index, opts),
        render_component(domain, entity, :show, opts),
        render_component(domain, entity, :form, opts)
      ]
    end)
  end

  @doc "Render a single component. `kind` is `:index`, `:show`, or `:form`."
  def render_component(%Domain{} = domain, %Entity{} = entity, kind, opts \\ []) do
    path = Naming.svelte_file_path(domain, entity.name, kind)
    existing = existing_path(path, opts)

    assigns = component_assigns(domain, entity, kind)
    template = Map.fetch!(kind_templates(), kind)

    source =
      EEx.eval_file(template, assigns: assigns, trim: true)
      |> merge_svelte(existing)

    {path, source}
  end

  # --- Template selection -------------------------------------------------

  defp kind_templates do
    %{
      index: @index_template,
      show: @show_template,
      form: @form_template
    }
  end

  # --- TypeScript interface assigns --------------------------------------

  defp ts_entity_assign(%Entity{} = entity) do
    fields =
      entity
      |> public_fields()
      |> Enum.map(fn f ->
        %{
          name: f.name,
          optional: not Keyword.get(f.opts || [], :required, false),
          ts_type: ts_type(f)
        }
      end)

    %{ts_name: Naming.camelize(Naming.singularize(entity.name)), ts_fields: fields}
  end

  # --- Component assigns --------------------------------------------------

  defp component_assigns(%Domain{} = domain, %Entity{} = entity, :index) do
    fields = public_fields(entity)
    singular = Naming.singular_string(entity.name)

    base_assigns(domain, entity, :index) ++
      [
        columns: Enum.map(fields, &index_column(&1, singular))
      ]
  end

  defp component_assigns(%Domain{} = domain, %Entity{} = entity, :show) do
    fields = public_fields(entity)
    singular = Naming.singular_string(entity.name)

    base_assigns(domain, entity, :show) ++
      [
        fields: Enum.map(fields, &show_field(&1, singular))
      ]
  end

  defp component_assigns(%Domain{} = domain, %Entity{} = entity, :form) do
    fields = public_fields(entity)
    singular = Naming.singular_string(entity.name)

    base_assigns(domain, entity, :form) ++
      [
        inputs: Enum.map(fields, &form_input(&1, singular))
      ]
  end

  defp base_assigns(%Domain{} = domain, %Entity{} = entity, _kind) do
    singular = Naming.singular_string(entity.name)
    plural = Naming.plural_string(entity.name)

    [
      domain_module: inspect(domain.module),
      entity_ts: Naming.camelize(Naming.singularize(entity.name)),
      singular: singular,
      plural: plural,
      types_import: types_import_path(domain)
    ]
  end

  # Relative import from the Svelte file to the types file.
  # svelte_file: assets/svelte/[v1/]library/BookIndex.svelte
  # types_file:  assets/svelte/[v1/]types/library.ts
  #
  # Both sit under the same `v1/` (or root) scope, so the relative path
  # is always `../types/<context>`.
  defp types_import_path(%Domain{} = domain) do
    ctx_short = Naming.context_short(domain)
    "../types/#{ctx_short}"
  end

  # --- Per-field rendering ------------------------------------------------

  defp index_column(%Field{name: name, type: type}, row_var) do
    %{label: humanize(name), cell: svelte_cell_expression(name, type, row_var)}
  end

  defp show_field(%Field{name: name, type: type}, row_var) do
    %{label: humanize(name), cell: svelte_cell_expression(name, type, row_var)}
  end

  defp form_input(%Field{name: name, type: type, opts: opts}, row_var) do
    required? = Keyword.get(opts || [], :required, false)

    %{
      name: name,
      label: humanize(name),
      required: required?,
      control: form_input_control(name, type, row_var)
    }
  end

  defp svelte_cell_expression(name, :boolean, row_var),
    do: "{#{row_var}.#{name} ? '✓' : '—'}"

  defp svelte_cell_expression(name, _type, row_var),
    do: "{#{row_var}.#{name} ?? '—'}"

  defp form_input_control(name, :boolean, row_var) do
    """
    <input
        type="checkbox"
        checked={#{row_var}.#{name} ?? false}
        onchange={(e) => handleChange('#{name}', e.currentTarget.checked)}
      />\
    """
  end

  defp form_input_control(name, :text, row_var) do
    """
    <textarea
        value={#{row_var}.#{name} ?? ''}
        oninput={(e) => handleChange('#{name}', e.currentTarget.value)}
      />\
    """
  end

  defp form_input_control(name, type, row_var)
       when type in [:integer, :bigint, :float, :decimal] do
    """
    <input
        type="number"
        value={#{row_var}.#{name} ?? ''}
        oninput={(e) => handleChange('#{name}', e.currentTarget.value)}
      />\
    """
  end

  defp form_input_control(name, :date, row_var) do
    """
    <input
        type="date"
        value={#{row_var}.#{name} ?? ''}
        oninput={(e) => handleChange('#{name}', e.currentTarget.value)}
      />\
    """
  end

  defp form_input_control(name, _type, row_var) do
    """
    <input
        type="text"
        value={#{row_var}.#{name} ?? ''}
        oninput={(e) => handleChange('#{name}', e.currentTarget.value)}
      />\
    """
  end

  # --- Scalar mapping -----------------------------------------------------

  defp ts_type(%Field{type: type}) do
    case type do
      t when t in [:string, :text] -> "string"
      t when t in [:binary, :binary_id, :uuid] -> "string"
      t when t in [:integer, :bigint, :float] -> "number"
      :decimal -> "string"
      :boolean -> "boolean"
      t when t in [:date, :time, :naive_datetime, :utc_datetime] -> "string"
      t when t in [:map, :json, :jsonb] -> "Record<string, unknown>"
      _ -> "unknown"
    end
  end

  # --- Utilities ----------------------------------------------------------

  # Fields safe to send to the Svelte client: drop tenant_id and any
  # auth-redacted credential field (hashed_password, api_tokens).
  # `confirmed_at` is kept — it's useful for the UI to gate features on
  # email confirmation.
  defp public_fields(%Entity{fields: fields}) do
    Enum.reject(fields, fn f -> Tenant.injected?(f) or auth_redacted?(f) end)
  end

  defp auth_redacted?(%Field{opts: opts}) do
    Keyword.get(opts || [], :auth) in [:password, :api_token] or
      Keyword.get(opts || [], :redact, false) == true
  end

  @doc false
  def public_fields_for(entity), do: public_fields(entity)

  defp humanize(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # --- CUSTOM-marker merging ---------------------------------------------

  @ts_marker "// --- CUSTOM ---"
  @svelte_marker "<!-- --- CUSTOM --- -->"

  defp merge_ts(new_source, path) do
    case File.read(path) do
      {:ok, existing} -> merge_marker(new_source, existing, @ts_marker)
      {:error, _} -> new_source
    end
  end

  defp merge_svelte(new_source, path) do
    case File.read(path) do
      {:ok, existing} -> merge_marker(new_source, existing, @svelte_marker)
      {:error, _} -> new_source
    end
  end

  defp merge_marker(new_source, existing_source, marker) do
    case String.split(existing_source, marker, parts: 2) do
      [_, rest] ->
        case String.split(new_source, marker, parts: 2) do
          [head, _] -> head <> marker <> rest
          _ -> new_source
        end

      _ ->
        new_source
    end
  end

  defp existing_path(path, opts) do
    root = Keyword.get(opts, :root, File.cwd!())
    Path.join(root, path)
  end
end
