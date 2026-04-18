<p align="center">
  <img src="assets/logo.svg" alt="Caravela" width="180" height="180"/>
</p>

# Caravela

*Declare your domain. Sail with the generated code.*

A schema-driven, composable full-stack framework for Phoenix projects.
Describe a domain (entities, fields, relations, hooks, permissions) as
an Elixir DSL; Caravela generates Ecto schemas, migrations, Phoenix
contexts, JSON controllers, Absinthe schemas, and LiveView + typed
Svelte components.

```elixir
defmodule MyApp.Domains.Library do
  use Caravela.Domain, multi_tenant: true

  version "v1"

  entity :books do
    field :title, :string, required: true, min_length: 3
    field :published, :boolean, default: false
  end

  can_create :books, fn ctx -> ctx.current_user.role in [:admin, :editor] end
end
```

```bash
mix caravela.gen MyApp.Domains.Library
mix caravela.gen.live MyApp.Domains.Library
```

## Install

```elixir
{:caravela, "~> 0.8.0"}
```

## Documentation

- 📘 **HexDocs**: <https://hexdocs.pm/caravela>
- 🌐 **Site**: <https://rsousacode.github.io/Caravela>

Full guides live under `docs/` and ship with the Hex package.

- [Getting started](docs/getting_started.md)
- [DSL reference](docs/dsl.md)
- [Generators](docs/generators.md)
- [Multi-tenancy](docs/multi_tenancy.md)
- [API versioning](docs/versioning.md)
- [GraphQL with Absinthe](docs/graphql.md)
- [LiveSvelte frontend](docs/livesvelte.md)
- [Live runtime (`Caravela.Live.*`)](docs/live_runtime.md)
- [Flows — async workflow orchestration](docs/flows.md)
- [Regeneration & the CUSTOM marker](docs/regeneration.md)
- [Authentication (`authenticatable`)](docs/auth.md)
- [Policies — triple-target authorization](docs/policies.md)

Run `mix docs` to build the full API reference locally (HexDocs-style).

## Status

Phases 1–5 are in place: DSL + compiler, Ecto schemas + migrations,
hooks + permissions, Phoenix contexts, JSON API, Absinthe/GraphQL,
multi-tenancy, API versioning, LiveSvelte generation, the
`Caravela.Live.*` runtime, dynamic Svelte forms with visibility
predicates + async validation, and a GenServer-backed flow runtime
(`Caravela.Flow`) for composable async workflows. Phases 7–8 add
trait-based authentication — declare `authenticatable` on an entity
and `mix caravela.gen.auth` emits the full email/password + API-token
stack plus matching LiveSvelte UI. Phase 9 adds **triple-target
policies** — one `policy` block compiles into Ecto WHERE clauses,
field projection on every API/GraphQL response, and a typed
`field_access` Svelte prop, all enforced server-side.

## License

MPL-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Use Caravela freely, including in closed-source apps. Modifications to
Caravela source files must stay under MPL-2.0 with attribution.

## Support the project

Caravela is built in the open and free to use. Donation channels will
be linked here once set up. PRs, bug reports, and kind words all help
keep the sails full.
