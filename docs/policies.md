# Policies — one declaration, three enforced layers

Caravela's `policy` block is the framework's core authorization
primitive. A single declaration compiles into **three simultaneous
enforcement targets**:

1. **Ecto WHERE clauses** — row-level scope on every read.
2. **Field projection** — invisible fields are redacted from every
   record before it leaves the context (JSON + GraphQL ride on this
   automatically).
3. **Typed Svelte `field_access` prop** — the generated Svelte
   components gate columns/fields/inputs with `{#if field_access.x}`
   so the UI never renders controls the actor shouldn't see.

No three-way sync. No drift. The client could ignore the prop and the
data still wouldn't be there — the server already stripped it.

## DSL

```elixir
defmodule MyApp.Domains.Library do
  use Caravela.Domain, multi_tenant: true
  version "v1"

  import Ecto.Query, only: [where: 3]

  entity :books do
    field :title, :string, required: true
    field :isbn, :string
    field :published, :boolean, default: false
    field :price, :decimal, precision: 10, scale: 2
    field :internal_notes, :text
    field :cost_basis, :decimal
    field :author_email, :string
  end

  policy :books do
    # Row-level: which records can this actor see?
    scope fn query, actor ->
      case actor.role do
        :admin -> query
        _ -> where(query, [b], b.published == true)
      end
    end

    # Field-level: which fields can this actor see on accessible records?
    field :price,          visible: fn actor -> actor.role in [:admin, :editor] end
    field :internal_notes, visible: fn actor -> actor.role == :admin end
    field :cost_basis,     visible: fn actor -> actor.role == :admin end

    # Record-dependent rules — the field drops per row.
    field :author_email,   visible: fn actor, record ->
      actor.role == :admin or actor.id == record.author_id
    end

    # Action-level: who can create/update/delete?
    allow :create, fn actor -> actor.role in [:admin, :editor] end
    allow :update, fn actor, record ->
      actor.role == :admin or actor.id == record.author_id
    end
    allow :delete, fn actor -> actor.role == :admin end
  end
end
```

### Rules

- `scope fn query, actor -> query end` — exactly one per entity.
  Applied to every read in the generated context.
- `field :name, visible: fn actor -> bool end` — arity 1. Constant
  per request. The Svelte `field_access` prop carries the resolved
  boolean.
- `field :name, visible: fn actor, record -> bool end` — arity 2.
  Record-dependent. The prop resolves to the sentinel `'per_record'`
  and each row is evaluated server-side; denied rows simply have the
  field set to `null`.
- `allow :create | :update | :delete, fn actor[, record] -> bool end`
  — gates the context's `create_*` / `update_*` / `delete_*` functions.

### Actor lookup

The actor is `context.current_user` (or the string key
`"current_user"`). The authenticatable trait from
[docs/auth.md](auth.md) sets it for you via `on_mount` hooks and the
`fetch_current_user` plug.

## What the compiler generates

For each `policy :entity` block, the compiler emits three dispatch
functions on the domain module:

- `__caravela_policy_scope__/3`         — `(entity, query, actor)`
- `__caravela_policy_field_visible__/3` — `(entity, field, actor)`
- `__caravela_policy_field_visible__/4` — `(entity, field, actor, record)`
- `__caravela_policy_allow__/3`         — `(entity, action, actor)`
- `__caravela_policy_allow__/4`         — `(entity, action, actor, record)`

Each unpolicied entity falls through to a no-op default (`query`
unchanged, visibility `true`, allow `true`). Adding or removing a
policy never breaks existing call sites.

The generated context then exposes:

- `field_access(entity, context)` — the typed map passed to Svelte
  via LiveSvelte.
- `list_*` / `get_*` — read paths apply the scope *and* the field
  projection before returning.
- `create_*` / `update_*` / `delete_*` — write paths hit both the
  existing `can_*` check AND the new `allow` gate.

## TypeScript + Svelte shape

Generated `assets/svelte/[v<N>/]types/<context>.ts`:

```ts
export interface BookFieldAccess {
  title: true;                // no rule → constant true
  price: boolean;              // arity-1 → boolean
  internal_notes: boolean;
  cost_basis: boolean;
  author_email: 'per_record';  // arity-2 → per-row, field may be null
}
```

Generated Svelte components accept it as a typed prop:

```svelte
<script lang="ts">
  import type { Book, BookFieldAccess, LiveHandle } from '../types/library';

  let {
    books = [],
    field_access = { title: true, isbn: true, published: true, price: true, ... },
    live
  }: {
    books?: Book[];
    field_access?: BookFieldAccess;
    live: LiveHandle;
  } = $props();
</script>

<table>
  <thead>
    <tr>
      <th>Title</th>
      {#if field_access.price}<th>Price</th>{/if}
      {#if field_access.internal_notes}<th>Notes</th>{/if}
    </tr>
  </thead>
  <!-- ... -->
</table>
```

Fields without a rule are rendered unconditionally; fields with a rule
are wrapped in `{#if field_access.<name>}`.

## Security model

- **The server is the authority.** Field projection strips data
  *before* it hits the wire. Row scoping limits what the DB ever
  returns. A malicious client ignoring `field_access` still cannot see
  redacted fields — the bytes were never sent.
- **Per-record rules evaluate per row.** The TypeScript prop says
  `'per_record'` so the client knows the field is *sometimes* present,
  *sometimes* null. Your Svelte code typically renders it with a
  fallback (`{book.author_email ?? '—'}`).
- **Defaults are safe on the client, permissive on the server.** A
  component mounted without LiveView wiring (e.g. in a Storybook
  scenario) renders every field — the default prop is all-true. The
  server-side fallback in the domain module is also all-true, so
  entities without any declared policy behave as before.

## Backward compatibility

Existing `can_read :books, fn query, context -> ... end` hooks and
`can_create` / `can_update` / `can_delete` from Phase 2 continue to
work — they run **before** the policy scope/allow gates, not instead
of them. Either subsystem alone is enough; combining both produces
strictly-more-restrictive access (intersection of both rule sets),
which is the safe direction to fail.

Start with `can_*` when you only need row filtering; upgrade to
`policy` when you need field masking or want the same rules enforced
on your Svelte UI.
