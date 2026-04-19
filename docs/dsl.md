# DSL reference

Every Caravela domain is a module that `use`s `Caravela.Domain`. The
DSL declares entities, relations, lifecycle hooks, and authorization
rules; the compiler builds an IR and validates it before generators
run.

## `entity :<name>, opts \\ [] do ... end`

Declares one entity (one database table). The name is plural
(`:books`); the generator derives a singular module name (`Book`), a
plural table name (`library_books`), and a path
(`lib/<app>/library/book.ex`).

```elixir
entity :books do
  field :title, :string, required: true
  field :isbn, :string
end
```

### Entity options

The keyword list between the name and the `do` block selects render
mode and real-time behaviour. Omit it and Caravela defaults to
`frontend: :live, realtime: false`.

| option       | values                 | effect                                                          |
|--------------|------------------------|-----------------------------------------------------------------|
| `:frontend`  | `:live` (default) / `:rest` | Which transport the generated UI uses. See [svelte frontend](livesvelte.md). |
| `:realtime`  | `true` / `false` (default)  | SSE-driven live updates on top of `:rest`. Requires `frontend: :rest` — rejected on `:live` entities (LiveView already has a WebSocket). |

```elixir
# Classic LiveView + WebSocket.
entity :authors do
  field :name, :string, required: true
end

# Inertia-style HTTP transport via caravela_svelte.
entity :books, frontend: :rest do
  field :title, :string, required: true
end

# REST page with per-actor SSE updates on create / update / delete.
entity :orders, frontend: :rest, realtime: true do
  field :total, :decimal, precision: 10, scale: 2
end
```

A single domain can mix both modes — `caravela_routes` in the router
picks the right transport per entity automatically.

Invalid option values (`frontend: :graphql`, non-boolean `realtime`,
or unknown keys) raise `Caravela.DSLError` with actionable
suggestions at compile time.

## `field :<name>, <type>, opts`

| option                     | applies to        | effect                              |
|----------------------------|-------------------|-------------------------------------|
| `required`                 | any               | `null: false` + `validate_required` |
| `default`                  | any               | column default                      |
| `min`, `max`               | numeric           | `validate_number`                   |
| `min_length`, `max_length` | string-like       | `validate_length`                   |
| `format`                   | string-like       | `validate_format` (regex)           |
| `precision`, `scale`       | numeric           | decimal precision/scale             |

**Recognised types:** `:string`, `:text`, `:integer`, `:bigint`,
`:float`, `:decimal`, `:boolean`, `:date`, `:time`, `:naive_datetime`,
`:utc_datetime`, `:binary`, `:binary_id`, `:uuid`, `:map`, `:json`,
`:jsonb`.

## `relation :<from>, :<to>, type: <t>`

`t` is one of `:has_many`, `:has_one`, `:belongs_to`, `:many_to_many`.
Declare either side of a relationship — Caravela infers the other.

```elixir
relation :authors, :books,   type: :has_many
relation :books,   :publishers, type: :belongs_to, required: true
```

`required: true` on a `:belongs_to` produces `null: false` on the FK
and `on_delete: :delete_all` in the migration.

## `version "v<n>"` *(optional)*

Declares the domain's API version. When set, generated modules and
routes are namespaced under the version segment. See
[versioning](versioning.md).

```elixir
use Caravela.Domain
version "v1"
```

## `use Caravela.Domain, multi_tenant: true` *(optional)*

Opts the domain into row-level multi-tenancy: a `:tenant_id`
(`:binary_id`, `null: false`) field is auto-injected into every
entity, and the generated context scopes reads/writes by
`context.tenant.id`. See [multi-tenancy](multi_tenancy.md).

## Hooks: `on_create`, `on_update`, `on_delete`

Hooks run inside the generated context, between authorization and the
final `Repo` call:

```elixir
on_create :books, fn changeset, context -> ... end     # → changeset
on_update :books, fn changeset, context -> ... end     # → changeset
on_delete :authors, fn author, context -> ... end      # → :ok | {:error, reason}
```

`context` is whatever map you pass to the context function. In the
generated controllers it defaults to `%{current_user: …, conn: conn}`
(plus `tenant:` when `multi_tenant: true`).

If `{:error, reason}` is returned from `on_delete`, the delete is
aborted and the tuple propagates back to the caller.

## Authorization: `policy` blocks

Caravela's authorization is declared via `policy :entity do … end`
blocks. A single policy compiles into three enforcement targets —
Ecto `WHERE` clauses, field-level projection on API responses, and a
typed `field_access` Svelte prop — so UI, API, and database stay in
sync automatically. See [Policies](policies.md) for the full guide.

```elixir
policy :books do
  scope fn query, actor ->
    if actor.role == :admin, do: query, else: where(query, [b], b.published)
  end

  field :price, visible: fn actor -> actor.role in [:admin, :editor] end

  allow :create, fn actor -> actor.role in [:admin, :editor] end
  allow :update, fn actor, record ->
    actor.role == :admin or actor.id == record.author_id
  end
  allow :delete, fn actor -> actor.role == :admin end
end
```

To use query macros like `where` / `from` inside `scope`, add
`import Ecto.Query` at the top of your domain module.

## Compile-time validations

Every rule raises a `CompileError` pointing at the offending line:

1. Unknown field types (`:widget` etc.)
2. Numeric constraints on non-numeric fields (and vice versa)
3. Duplicate entity names
4. Relations referencing undeclared entities
5. Incompatible cardinality (e.g. both sides `:has_many`)
6. Circular chains of required `belongs_to` (unsatisfiable inserts)
7. Hooks / policy rules with the wrong function arity
8. Hooks / policies referring to unknown entities or fields
9. Duplicate hook for the same (action, entity), or duplicate `policy` block
10. Version strings that don't match `~r/^v\d+$/`
11. Manual `tenant_id` fields in a `multi_tenant: true` domain
