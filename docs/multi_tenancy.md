# Multi-tenancy

Caravela supports row-level multi-tenancy via a single DSL flag:

```elixir
defmodule MyApp.Domains.Library do
  use Caravela.Domain, multi_tenant: true

  entity :books do
    field :title, :string, required: true
    # tenant_id is auto-injected — don't declare it
  end
end
```

## What changes

**Schemas & migrations.** A `:tenant_id` `:binary_id` column
(`null: false`) is added to every entity. Migrations add composite
`[:tenant_id, :<fk>]` indexes alongside each foreign-key index, plus a
standalone `[:tenant_id]` index on tables with no FKs.

**Context.** The generated context scopes every read with
`where(q.tenant_id == ^tenant_id)` and stamps every create with
`put_change(:tenant_id, tenant_id)` — both driven by `context.tenant.id`
at the call site. When the caller's context has no `:tenant`, the
scoping helpers no-op (useful for background jobs that deliberately
cross tenants).

**Controllers & LiveViews.** Generated controllers read
`conn.assigns[:tenant]` into the context automatically. Same for
generated LiveViews reading `socket.assigns[:tenant]`. You plug the
tenant in ahead of your `:api` or `:browser` pipeline — from a
subdomain, header, or session claim — Caravela only consumes it.

**GraphQL.** The Absinthe input objects hide `tenant_id`; tenant id
comes from the resolver's Absinthe context, not the client.

## Why row-level (and not prefix-based)

Ecto's prefix-based multi-tenancy requires per-tenant migration runs,
repo reconfiguration, and is hard to debug. Row-level is explicit,
standard, and works with a single database schema.

The entire multi-tenant machinery is one compile-time injection
(`Caravela.Tenant.inject/1`) plus three lines in the context template.
If you need to eject, it's trivial to remove.

## Compile-time guard

If an entity tries to declare a `:tenant_id` field manually in a
`multi_tenant: true` domain, the compiler raises:

    ** (CompileError) Caravela: entity :books declares a :tenant_id field,
    but the domain has multi_tenant: true — tenant_id is auto-injected.

## Caveats

- Caravela does not enforce tenant isolation at the DB level (no RLS).
  It's the application layer's responsibility to pass the right tenant
  into the context. Scoping helpers make this impossible to forget for
  generated call paths, but anything you hand-write has to opt in.
- The composite indexes assume tenant queries will be the common case.
  If you run a lot of cross-tenant admin queries, you may want extra
  indexes on `[:<fk>]` alone; add them in a follow-up migration.
