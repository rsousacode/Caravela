# Regeneration

Caravela regenerates files from the domain IR every time you run a
`mix caravela.gen.*` task. Two mechanisms cooperate to keep user edits
safe across re-runs:

1. A **checksum header** on every generated file detects unexpected
   edits above the `CUSTOM` marker and aborts rather than overwriting
   them.
2. **`CUSTOM` markers** carve out user-owned regions: a single tail
   marker per file, plus per-function named markers placed at every
   natural extension point.

Both work together — edits in user-owned regions are preserved
verbatim; edits in generator-owned regions are caught before they're
silently stomped.

## Anatomy of a generated file

```elixir
# caravela-gen: generator=context version=0.8.1 above_sha256=c8d8024…
defmodule MyApp.Library do
  @moduledoc "..."

  def list_books(context \\ %{}) do
    Book
    |> scope_tenant(context)
    |> Repo.all()
  end

  # --- CUSTOM :list_books ---
  # --- END :list_books ---

  def get_book(id, context \\ %{}) do
    # ...
  end

  # --- CUSTOM :get_book ---
  # --- END :get_book ---

  # ... more generated functions + named blocks ...

  # --- CUSTOM ---
  # Custom code below this line is preserved on regeneration.
end
```

Three zones, three ownership stories:

| Zone | Who owns it | Regen behavior |
|---|---|---|
| Generator output (top of file through marker lines) | Caravela | Re-emitted every run. Edits → checksum aborts the run. |
| Named `:xxx` blocks (between `CUSTOM :name` / `END :name`) | User | Preserved by name on regen. Edits inside → no-op for the checksum. |
| Tail `# --- CUSTOM ---` section (bottom of file) | User | Preserved verbatim. For freeform helpers that don't fit a named block. |

## The checksum header

The first line of every generated file records the generator name, the
Caravela version that produced the file, and an sha256 over the
generator-owned content:

```
# caravela-gen: generator=context version=0.8.1 above_sha256=c8d8024f…
```

For TypeScript outputs the comment is `// caravela-gen: …`; for Svelte
components it's `<!-- caravela-gen: … -->`.

**What the hash covers.** Everything above the tail `CUSTOM` marker,
*with named-block bodies normalised to empty*. Concretely:

- User edits inside a `# --- CUSTOM :foo ---` block → hash unchanged.
- User edits anywhere else above the tail marker → hash changes.
- User deletes a named block's markers entirely → hash changes (the
  scaffolding structure differs).
- User adds content below the tail marker → hash unchanged (the hash
  stops at the tail marker).

**What happens on mismatch.** The generator prints a diff of the
stored vs. current hash and three remediation steps, then aborts via
`Mix.raise/1`. Your edits stay on disk untouched. From there you can:

1. Move the edits below the `# --- CUSTOM ---` marker (or into a
   named `:xxx` block) and re-run the generator cleanly, or
2. Re-run with `--force` to overwrite — Caravela prints a yellow
   warning recording what was discarded, or
3. Re-run with `--dry-run` to inspect what Caravela wants to write
   before committing to either of the above.

**First upgrade.** A file without a `caravela-gen:` header is treated
as "unheadered legacy" and stamped silently on the next regen. No
mismatch, no warning.

## The tail `CUSTOM` marker

The traditional escape hatch. Put anything here: helper modules, local
structs, unrelated helpers, miscellaneous notes. Regen preserves the
tail verbatim.

```elixir
  # --- CUSTOM ---
  # Custom code below this line is preserved on regeneration.
  defp my_helper(ctx), do: ...
end
```

Svelte files use `<!-- --- CUSTOM --- -->`; TypeScript files use
`// --- CUSTOM ---`.

## Per-function named `CUSTOM` blocks

Each Elixir-style generator emits named marker pairs at its natural
extension points. Write user code *between* the markers; it survives
regen by name.

```elixir
def list_books(context \\ %{}) do
  Book
  |> scope_tenant(context)
  |> Repo.all()
end

# --- CUSTOM :list_books ---
defp scope_to_published(query), do: where(query, [b], b.published)
# --- END :list_books ---
```

Where the markers live, per generator:

| Generator | Named block(s) per entity / action |
|---|---|
| `context` | `:list_<e>`, `:get_<e>`, `:create_<e>`, `:update_<e>`, `:delete_<e>` |
| `controller` | `:index_<s>`, `:show_<s>`, `:create_<s>`, `:update_<s>`, `:delete_<s>` |
| `ecto_schema` | `:changeset` |
| `graphql_types` | `:type_<gql_name>` per entity |
| `graphql_queries` | `:queries_<singular>` per entity |
| `graphql_mutations` | `:mutations_<singular>` per entity |
| `live_view` (index/show/form) | `:mount_*`, `:handle_event_*` per kind per entity |
| `live_form_domain` | `:updaters_<singular>` |
| `auth_context` | `:register`, `:login`, `:logout`, `:reset_password`, `:confirm_email` |
| `auth_controller` | `:auth_controller_register`, `:…_login`, `:…_logout` |
| `auth_plugs` | `:auth_plugs` |
| `auth_live_*` | one per page (login / register / confirm_email / reset_password / session_list / token_manager) |

Named blocks are an **Elixir-only** feature. Svelte and TypeScript
outputs rely on the tail marker + checksum.

**Adding a field, renaming an entity, etc.** When the generator stops
emitting a named block (because you removed the corresponding entity
or the template no longer covers that extension point), the block
becomes an *orphan*. Regen prints a yellow warning listing every
orphan name and discards the content:

```
warning: orphan CUSTOM blocks dropped during regen:
    :list_old_entity
  These named blocks no longer have a home in the generator output.
  Recover from git history if you need the content.
```

Discard is intentional — keeping phantom blocks around with no
structural home invites confusion. Recover from git if the content
matters.

## Migrations are not merged

Every `mix caravela.gen.schema` (and the all-in-one `mix caravela.gen`)
emits a **new** migration file with a fresh timestamp. It contains
the full desired schema — not a diff. Caravela is *stateless about
schema evolution*: it produces the desired state; you (or your LLM)
write the bridging `ALTER TABLE` migration with
`mix ecto.gen.migration`.

There is no checksum header on migrations — they're one-shot
artifacts, owned by you from the moment they're written.

## Router is not edited

Caravela doesn't touch `router.ex`. `mix caravela.gen.api` and
`mix caravela.gen.auth` **print** a scope snippet for you to paste
once; after that, the router is yours to evolve.

## Flag summary

| Flag | Effect |
|---|---|
| `--dry-run` | Print generated files without writing. Useful for previewing a regen against an existing tree. |
| `--force` | Bypass both the "file exists" prompt *and* the checksum verification. Prints a yellow warning with the stored / current hashes for any file whose above-marker region was edited. |
| `--output DIR` | Write under `DIR` instead of the project root. |

Available on every `mix caravela.gen.*` task.

## Why this design

- **No silent stomping.** The pre-0.8.1 `CUSTOM`-marker mechanism
  merged blindly: edits above the marker were overwritten without
  warning. The sha256 header closes that gap.
- **Scoped extension points.** One tail marker per file is fine for
  miscellaneous helpers; for per-function customisation (a validator
  here, a hook there) the named blocks give reviewers a clear signal
  about which seam changed.
- **No AST merging.** Line-oriented sha256 + name-based block merge
  is dumb and predictable. No half-baked AST diff that breaks on a
  rename or a moved import.
- **Debuggable.** Every file carries its generator name and the
  version of Caravela that wrote it. `grep caravela-gen: lib/**` at
  any time to audit what's under the generator's stewardship.
