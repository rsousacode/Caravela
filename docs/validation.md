# Validation and changeset errors

Caravela's generated forms and REST controllers translate
`Ecto.Changeset` errors into a structured, i18n-ready shape via
`Caravela.ChangesetTranslator`. The shape is semver-stable from
v0.12 onward.

## The error shape

Every field's error list is a sequence of structured maps:

```elixir
%{
  title: [
    %{code: :required, params: %{}, message: "can't be blank"}
  ],
  pages: [
    %{code: :number, params: %{kind: :greater_than, number: 0}, message: "must be greater than 0"}
  ]
}
```

- **`:code`** is Ecto's `:validation` option when present, then
  `:constraint`, then `:invalid` as a fallback. Stable across locales
  and Ecto versions - frontends key their translations on it.
- **`:params`** is the original Ecto error options with
  `:validation` / `:constraint` stripped (they're promoted to
  `:code`). Carries `:count`, `:kind`, `:max`, `:number`, etc. that
  translation templates interpolate.
- **`:message`** is the rendered string. Filled by the configured
  translator (below), or by the built-in pass-through interpolator
  that replaces `%{param}` placeholders.

## Gettext integration

Apps using Gettext plug their backend in `config.exs`:

```elixir
# config/config.exs
config :caravela, :changeset_translator, MyAppWeb.Gettext
```

Caravela calls `MyAppWeb.Gettext.dgettext("errors", template, params)`
for singular messages and `MyAppWeb.Gettext.dngettext("errors",
singular, plural, count, params)` when Ecto signals a plural via the
`:count` option - the same contract Phoenix's own
`ErrorHelpers.translate_error/1` uses. Existing
`priv/gettext/<locale>/LC_MESSAGES/errors.po` locale files work
unchanged.

Any module that exports `dgettext/3` and `dngettext/5` is a valid
translator - Gettext backends are the common case but not a
requirement.

## Per-call override

```elixir
Caravela.ChangesetTranslator.translate(changeset, translator: OtherBackend)

# Or force the pass-through path (no translation) - useful in tests:
Caravela.ChangesetTranslator.translate(changeset, translator: false)
```

## Using it outside generated code

`Caravela.ChangesetTranslator.translate/2` is a public helper. Call it
from any controller or LiveView that needs the structured shape - it
isn't tied to Caravela-generated code:

```elixir
{:error, %Ecto.Changeset{} = cs} ->
  conn
  |> put_status(:unprocessable_entity)
  |> json(%{errors: Caravela.ChangesetTranslator.translate(cs)})
```

`translate_error/2` is also exposed for callers with their own
changeset traversal:

```elixir
Caravela.ChangesetTranslator.translate_error(
  {"is invalid", [validation: :format]},
  translator: false
)
#=> %{code: :format, params: %{}, message: "is invalid"}
```

## On the frontend

Generated Svelte form components (`BookForm.svelte`) receive errors
as:

```ts
errors?: Record<string, Array<{ code: string; params: object; message: string }>>;
```

A simple renderer reads `:message` directly; a localized renderer keys
on `:code` and interpolates `:params`:

```svelte
{#each errors.title ?? [] as err}
  {#if err.code === 'required'}
    <span class="error">{$_('errors.required')}</span>
  {:else if err.code === 'length'}
    <span class="error">
      {$_('errors.too_short', { values: { count: err.params.count } })}
    </span>
  {:else}
    <span class="error">{err.message}</span>
  {/if}
{/each}
```

The `:rest` REST controller and the `:live` LiveView form both
produce this shape, so the same Svelte error component works under
either transport. See [svelte frontend](livesvelte.md) for the full
prop contract.

## Migration note (v0.11 → v0.12)

Prior to v0.12 the generated templates delegated to
`CaravelaSvelte.Caravela.errors/1`, which produced the flat Phoenix
`%{field => [msg]}` shape. That helper still exists in
`caravela_svelte` for backward compatibility, but Caravela-generated
code no longer uses it. Re-running `mix caravela.gen.live` on an
existing domain rewrites the templates to use
`Caravela.ChangesetTranslator` and threads the structured shape
through the Svelte components' `errors` prop.
