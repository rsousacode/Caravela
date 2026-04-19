defmodule Caravela.Gen.SvelteForm do
  @moduledoc """
  Generates a dynamic Svelte form component from a module that declares
  `use Caravela.Live.Form`. The emitted component receives
  `field_visibility` and `async_errors` as props and wraps visibility-
  gated fields in `{#if field_visibility.<name>}` blocks.

  Unlike `Caravela.Gen.Svelte.render_component(domain, entity, :form)`,
  which emits a static `<Entity>Form.svelte`, this generator reads
  per-field visibility and async-validation metadata from the form
  module and emits `<Entity>FormDynamic.svelte` alongside it. The two
  coexist: plain-CRUD forms keep the static variant; forms using
  `visible`/`validate_async` use the dynamic one.

  Caller supplies the compiled form module (with `__caravela_form__/0`)
  plus the owning `Caravela.Schema.Domain` — the domain provides the
  entity's field/type list, which drives input control selection and
  the TypeScript import path.

      Caravela.Gen.SvelteForm.render(
        MyApp.BookFormDomain,
        MyApp.Domains.Library.__caravela_domain__()
      )
      #=> {"assets/svelte/library/BookFormDynamic.svelte", "<!-- ... -->"}

  Returns `{path, source}`. Preserves content below
  `<!-- --- CUSTOM --- -->` when regenerating.
  """

  alias Caravela.Schema.{Domain, Entity, Field}
  alias Caravela.{Gen, Naming, Tenant}

  @template Path.expand("../../../priv/templates/svelte_form_dynamic.eex", __DIR__)

  @doc """
  Render the dynamic Svelte form. `form_module` must use
  `Caravela.Live.Form`; `domain` is the `Caravela.Schema.Domain` that
  owns the entity referenced by the form.
  """
  def render(form_module, %Domain{} = domain, opts \\ []) when is_atom(form_module) do
    form_meta = form_module.__caravela_form__()
    entity = resolve_entity!(domain, form_meta.entity)

    path = dynamic_file_path(domain, entity.name)
    existing = existing_path(path, opts)

    assigns = build_assigns(form_module, form_meta, domain, entity)

    source =
      EEx.eval_file(@template, assigns: assigns, trim: true)
      |> Gen.Custom.merge_with_file(existing, style: :svelte, force: Keyword.get(opts, :force, false))
      |> Gen.Custom.stamp_header(style: :svelte, generator: :svelte_form_dynamic)

    {path, source}
  end

  @doc """
  File path for the dynamic Svelte form component, relative to project
  root. Mirrors `Caravela.Naming.svelte_file_path/3` but with the
  `FormDynamic` suffix.
  """
  def dynamic_file_path(%Domain{} = domain, entity_name) do
    ctx_short = Naming.context_short(domain)
    component = Naming.camelize(Naming.singularize(entity_name)) <> "FormDynamic"

    segments =
      case Domain.version(domain) do
        nil -> ["assets", "svelte", ctx_short]
        v -> ["assets", "svelte", v, ctx_short]
      end

    Path.join(segments ++ ["#{component}.svelte"])
  end

  # --- Resolve the Caravela entity referenced by the form module -------

  defp resolve_entity!(%Domain{} = domain, entity_ref) do
    case find_entity(domain, entity_ref) do
      {:ok, entity} ->
        entity

      :error ->
        raise ArgumentError,
              "Caravela.Gen.SvelteForm: could not find entity #{inspect(entity_ref)} " <>
                "in domain #{inspect(domain.module)}. The form's `entity:` option must " <>
                "reference an entity declared in the supplied domain."
    end
  end

  # `entity_ref` may be:
  #   * an atom entity name declared in the DSL (`:books`)
  #   * a compiled Ecto-schema module (`MyApp.Library.V1.Book`)
  defp find_entity(%Domain{entities: entities} = domain, ref) when is_atom(ref) do
    with nil <- Enum.find(entities, &(&1.name == ref)),
         nil <- find_by_module(domain, ref) do
      :error
    else
      %Entity{} = e -> {:ok, e}
    end
  end

  defp find_by_module(%Domain{} = domain, module) do
    Enum.find(domain.entities, fn e -> Naming.entity_module(domain, e.name) == module end)
  end

  # --- Template assigns --------------------------------------------------

  defp build_assigns(form_module, form_meta, %Domain{} = domain, %Entity{} = entity) do
    singular = Naming.singular_string(entity.name)
    visible_fields = form_meta.visible_fields
    debounces = form_meta.debounces

    async_fields =
      form_meta.async_fields
      |> Enum.map(fn f -> {f, Map.get(debounces, f, 0)} end)

    inputs =
      entity
      |> public_fields()
      |> Enum.map(&form_input(&1, singular, visible_fields, form_meta.async_fields))

    [
      form_module: inspect(form_module),
      domain_module: inspect(domain.module),
      entity_ts: Naming.camelize(Naming.singularize(entity.name)),
      singular: singular,
      types_import: types_import_path(domain),
      async_fields: async_fields,
      inputs: inputs
    ]
  end

  defp types_import_path(%Domain{} = domain) do
    "../types/#{Naming.context_short(domain)}"
  end

  defp public_fields(%Entity{fields: fields}) do
    Enum.reject(fields, &Tenant.injected?/1)
  end

  defp form_input(
         %Field{name: name, type: type, opts: opts},
         singular,
         visible_fields,
         async_fields
       ) do
    required? = Keyword.get(opts || [], :required, false)

    %{
      name: name,
      label: humanize(name),
      required: required?,
      visible?: name in visible_fields,
      async?: name in async_fields,
      control: form_input_control(name, type, singular)
    }
  end

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

  defp form_input_control(name, type, row_var) when type in [:naive_datetime, :utc_datetime] do
    """
    <input
        type="datetime-local"
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

  defp humanize(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp existing_path(path, opts) do
    root = Keyword.get(opts, :root, File.cwd!())
    Path.join(root, path)
  end
end
