defmodule Caravela.ChangesetTranslator do
  @moduledoc """
  Translate `Ecto.Changeset` errors into a structured, i18n-ready
  shape:

      %{field => [%{code: atom, params: map, message: String.t}]}

  The shape is semver-stable from 0.12 onward. Frontends (generated
  LiveView forms and REST controllers) key on `:code` to render
  localized UI; `:message` carries a rendered string for callers
  that don't own localization.

  ## Why structured

  Phoenix's out-of-the-box error format (`%{field => [msg]}`) is
  ergonomic but impossible to localize on the frontend — by the time
  the string reaches the Svelte layer, the structure is gone. Teams
  shipping beyond English have had to parse strings or re-validate
  client-side.

  Structured `%{code, params, message}` lets a frontend:

    * Key its translations on `:code` (stable across locales).
    * Interpolate `:params` (`%{count: 3}`) into its own
      translation template.
    * Fall back to `:message` when no frontend translation exists.

  The server still renders a `:message` — via the configured
  translator or a built-in pass-through interpolator — so
  monolingual apps need no extra setup.

  ## Configuring a translator

  Apps using Gettext plug their backend in:

      config :caravela, :changeset_translator, MyAppWeb.Gettext

  Caravela calls `MyAppWeb.Gettext.dgettext("errors", template, params)`
  (and `dngettext/5` for plural forms signalled via `:count`) — the
  exact pattern Phoenix's own `ErrorHelpers.translate_error/1` uses,
  so existing locale files under `priv/gettext/<locale>/LC_MESSAGES/
  errors.po` work unchanged.

  Per-call override:

      Caravela.ChangesetTranslator.translate(changeset, translator: OtherGettext)

  ## Custom translators

  Any module that exports `dgettext/3` and `dngettext/5` works —
  the contract matches Gettext backends. Pass `translator: false`
  to skip translation entirely and only interpolate parameters.

  ## Code extraction

  `:code` is Ecto's `:validation` option when present, then
  `:constraint`, then `:invalid` as a generic fallback. Ecto's
  sub-kinds (`kind: :min`, `kind: :greater_than`) stay in `:params`
  — consumers normalize to friendly codes (`:too_short`,
  `:too_large`) at their own discretion.
  """

  @type error :: %{code: atom(), params: map(), message: String.t()}
  @type errors :: %{optional(atom()) => [error()]}

  @doc """
  Translate every error on a changeset to the structured shape.

  Options:

    * `:translator` — an atom module exporting `dgettext/3` and
      `dngettext/5` (the Gettext backend contract). Falls back to
      the `config :caravela, :changeset_translator, _` value, and
      then to the pass-through interpolator when neither is set.
      Pass `false` to force the pass-through path (useful in tests).
  """
  @spec translate(Ecto.Changeset.t(), keyword()) :: errors()
  def translate(%Ecto.Changeset{} = changeset, opts \\ []) do
    translator = resolve_translator(Keyword.get(opts, :translator, :default))
    Ecto.Changeset.traverse_errors(changeset, &translate_error(&1, translator))
  end

  @doc """
  Translate a single `{msg, opts}` pair. Exposed so callers with
  their own traversal (e.g. generator templates that unwrap nested
  changesets before reporting) can reuse the same extraction logic.
  """
  @spec translate_error({String.t(), keyword()}, keyword()) :: error()
  def translate_error({msg, opts}, translator_opts) when is_list(translator_opts) do
    translator = resolve_translator(Keyword.get(translator_opts, :translator, :default))
    translate_error({msg, opts}, translator)
  end

  @spec translate_error({String.t(), keyword()}, module() | false | nil) :: error()
  def translate_error({msg, opts}, translator) do
    %{
      code: extract_code(opts),
      params: extract_params(opts),
      message: render_message(msg, opts, translator)
    }
  end

  # --- Internals ---------------------------------------------------------

  defp resolve_translator(:default),
    do: Application.get_env(:caravela, :changeset_translator)

  defp resolve_translator(false), do: false
  defp resolve_translator(nil), do: nil
  defp resolve_translator(mod) when is_atom(mod), do: mod

  defp extract_code(opts) do
    cond do
      validation = Keyword.get(opts, :validation) -> validation
      constraint = Keyword.get(opts, :constraint) -> constraint
      true -> :invalid
    end
  end

  # `:validation` / `:constraint` are metadata, not interpolation
  # parameters — drop them from `:params` so the frontend translation
  # doesn't receive noise. Everything else stays, including `:count`,
  # `:kind`, `:max`, etc. that templates interpolate.
  defp extract_params(opts) do
    opts
    |> Keyword.drop([:validation, :constraint])
    |> Enum.into(%{})
  end

  defp render_message(msg, opts, translator)
       when translator in [nil, false] do
    interpolate(msg, opts)
  end

  defp render_message(msg, opts, translator) when is_atom(translator) do
    cond do
      count = Keyword.get(opts, :count) ->
        translator.dngettext("errors", msg, msg, count, Enum.into(opts, %{}))

      true ->
        translator.dgettext("errors", msg, Enum.into(opts, %{}))
    end
  rescue
    # Translator module may not be loaded / may not export the expected
    # functions. Fall back to interpolation so the generated controller
    # still renders something the frontend can display.
    UndefinedFunctionError -> interpolate(msg, opts)
    ArgumentError -> interpolate(msg, opts)
  end

  defp interpolate(msg, opts) do
    Enum.reduce(opts, msg, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end
end
