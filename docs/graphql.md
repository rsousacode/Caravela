# GraphQL with Absinthe

`mix caravela.gen.graphql MyApp.Domains.Library` generates three files
under `lib/<app>_web/schema/`:

```
library_types.ex      # Absinthe object types, with dataloader relations
library_queries.ex    # list + single-fetch per entity
library_mutations.ex  # create / update / delete + typed input objects
```

All three delegate to the generated context module, so the same
authorization, hooks, and multi-tenant scoping you get from the REST
API flow through the Absinthe resolvers too.

## Dependencies

Absinthe is an **optional** Caravela dep. Add to your consumer app:

```elixir
{:absinthe, "~> 1.7"},
{:absinthe_plug, "~> 1.5"},
{:dataloader, "~> 2.0"}
```

`mix caravela.gen.graphql` checks at runtime and prints a pointed
error if any are missing.

## Example output

```elixir
# GENERATED: library_queries.ex
field :books, list_of(:book) do
  resolve fn _, _, resolution ->
    {:ok, Library.list_books(extract_context(resolution))}
  end
end

# GENERATED: library_mutations.ex
field :create_book, :book do
  arg :input, non_null(:book_input)

  resolve fn _, %{input: input}, resolution ->
    Library.create_book(input, extract_context(resolution))
  end
end
```

`extract_context/1` reads `%{context: ...}` from the Absinthe resolution
and passes it to the Caravela context. Plug your
`current_user`/`tenant` into `Absinthe.Plug` context — everything else
is automatic.

## What's hidden from GraphQL

**Tenant-injected fields.** When the domain is `multi_tenant: true`,
the input object omits `tenant_id`. Tenant id comes from the server
context, not the client.

**Inserted/updated timestamps.** Exposed in the object type (read-only);
not in input objects.

## Relations

Every relation becomes a dataloader-backed field:

```elixir
object :book do
  field :id, non_null(:id)
  field :title, non_null(:string)
  field :author, :author, resolve: dataloader(MyApp.Library)
end
```

Wire Dataloader into your Absinthe schema as usual. The Caravela
generator does not emit a Dataloader source — just the `resolve:`
reference — because the source composition depends on your Repo
setup. See Absinthe's Dataloader docs.

## Versioning

With `version "v1"`, the three files move under `schema/v1/` and module
names become `MyAppWeb.Schema.V1.LibraryTypes` etc. The Absinthe
schema you stitch together in `lib/<app>_web/schema.ex` imports the
types/queries/mutations per version — keep `/graphql/v1` and
`/graphql/v2` endpoints separate in your router.
