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

### The block is plain Elixir

The body of `policy :entity do … end` is a normal Elixir block, so
`for`, `if`, helper function calls, and module-attribute splicing all
work — the compiler expands them before our macros run:

```elixir
@admin_fields [:price, :cost_basis, :internal_notes]

policy :books do
  scope fn q, actor ->
    if actor.role == :admin, do: q, else: where(q, [b], b.published)
  end

  for f <- @admin_fields do
    field f, visible: fn actor -> actor.role == :admin end
  end

  if Mix.env() == :dev do
    allow :delete, fn _ -> true end
  end
end
```

Multiple `policy :entity` blocks are additive — useful for splitting
rules across files or wrapping one in an environment guard. Duplicate
rules *within* the same entity (two `scope`s, two `field :x`s, two
`allow :create`s) still raise at compile time, because silent
clause-ordering resolution is bewildering.

One limitation: `field :x, @some_opts` where `@some_opts` is a module
attribute reference raises a pointed error. The macro dispatches on
AST shape at compile time and can't see through the attribute. Either
inline the kw list or iterate with `for` over field names.

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

- `field_access(entity, context)` — per-field visibility map, passed
  to Svelte as the `field_access` prop.
- `action_access(entity, context)` — per-action map `%{create, update,
  delete}` with values `true`, `false`, or `:per_record`.
- `action_access(entity, record, context)` — same but resolves
  `:per_record` gates against a specific row. Use in index templates
  when the frontend needs per-row decisions.
- `list_*` / `get_*` — read paths apply the scope *and* the field
  projection before returning.
- `create_*` / `update_*` / `delete_*` — write paths run the
  corresponding `allow` gate before writing.

## TypeScript + Svelte shape

Generated `assets/svelte/[v<N>/]types/<context>.ts`:

```ts
// Field visibility — one entry per public field.
export interface BookFieldAccess {
  title: true;                 // no rule → constant true
  price: boolean;              // arity-1 → boolean
  internal_notes: boolean;
  cost_basis: boolean;
  author_email: 'per_record';  // arity-2 → per-row, field may be null
}

// Action gates — always the three standard actions.
export interface BookActions {
  create: boolean;                    // no gate or arity-1 → plain boolean
  update: boolean | 'per_record';     // arity-2 → may be deferred per-row
  delete: boolean;
}
```

Generated Svelte components accept both as typed props:

```svelte
<script lang="ts">
  import type { Book, BookFieldAccess, BookActions, LiveHandle } from '../types/library';

  let {
    books = [],
    field_access = { title: true, isbn: true, published: true, price: true, /* … */ },
    actions = { create: true, update: true, delete: true },
    live
  }: {
    books?: Book[];
    field_access?: BookFieldAccess;
    actions?: BookActions;
    live: LiveHandle;
  } = $props();
</script>

<div class="toolbar">
  {#if actions.create !== false}
    <button onclick={() => live.pushEvent('new', {})}>New book</button>
  {/if}
</div>

<table>
  <thead>
    <tr>
      <th>Title</th>
      {#if field_access.price}<th>Price</th>{/if}
      {#if field_access.internal_notes}<th>Notes</th>{/if}
      <th></th>
    </tr>
  </thead>
  <tbody>
    {#each books as book (book.id)}
      <tr>
        <td>{book.title}</td>
        {#if field_access.price}<td>{book.price}</td>{/if}
        {#if field_access.internal_notes}<td>{book.internal_notes}</td>{/if}
        <td>
          {#if actions.update === true}
            <button onclick={() => live.pushEvent('edit', { id: book.id })}>Edit</button>
          {/if}
          {#if actions.delete === true}
            <button onclick={() => live.pushEvent('delete', { id: book.id })}>Delete</button>
          {/if}
        </td>
      </tr>
    {/each}
  </tbody>
</table>
```

**Arity-2 action gates** (`allow :update, fn actor, record -> … end`)
can't resolve at the collection level — `actions.update` carries
`'per_record'` in index views. Resolve it server-side per row via
`action_access/3`, or skip the button and gate on
`actions.update === true` (the strict-equality check above
hides buttons unless the action is unconditionally allowed).

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
- **Deny-by-default.** Domains default to `default_policy: :deny`: any
  entity without a declared `policy` block has its scope filtered to
  zero rows, every field marked invisible, and every write denied.
  Forgetting to add a policy on a new entity can never silently leak
  data.

## `default_policy: :deny | :allow`

```elixir
# strict (default): entities without a policy block are fully denied
use Caravela.Domain

# explicit strict
use Caravela.Domain, default_policy: :deny

# opt out to permissive — entities without a policy block behave as
# if every field were visible and every action allowed
use Caravela.Domain, default_policy: :allow
```

Regardless of the domain default, **any entity that declares a policy
block is implicitly permissive for rule types it didn't declare**.
Writing `policy :books do field :price, visible: … end` grants full
scope + allow access for `:books` — only `:price` is gated. This keeps
policy blocks additive: you can start with a single field rule and
grow into scope/allow over time without accidentally locking the
entity out.

The decision tree for any (entity, rule) pair:

```
┌─ entity has a declared rule for this exact (action|field)? ──┐
│            ├── yes → use the declared rule                   │
│            └── no → entity has any `policy` block?           │
│                    ├── yes → permissive (true / pass-through)│
│                    └── no  → domain-level `default_policy`   │
└──────────────────────────────────────────────────────────────┘
```

## Authorization model

`policy` is the **only** authorization primitive. Earlier versions
shipped a separate `can_read` / `can_create` / `can_update` /
`can_delete` set of hooks — those were removed in 0.7.0 because they
ran alongside `policy` with no coordination (see the 0.7.0 changelog
entry). If you're migrating from an earlier release, move every
`can_*` rule into a `policy :entity do … end` block:

| Old                                 | New                                         |
|-------------------------------------|---------------------------------------------|
| `can_read :books, fn q, ctx -> … end` | `policy :books do scope fn q, actor -> … end end` |
| `can_create :books, fn ctx -> … end`  | `allow :create, fn actor -> … end`          |
| `can_update :books, fn b, ctx -> … end` | `allow :update, fn actor, record -> … end` |
| `can_delete :books, fn b, ctx -> … end` | `allow :delete, fn actor, record -> … end` |

The rule function now receives the **actor** (`context.current_user`)
directly instead of the raw context map, so references to
`context.current_user.role` become just `actor.role`.
