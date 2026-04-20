<p align="center">
  <img src="assets/logo.svg" alt="Caravela" width="180" height="180"/>
</p>

# Caravela

*Declare your domain. Sail with the generated code.*

A schema-driven, composable full-stack framework for Phoenix projects.
Describe a domain (entities, fields, relations, hooks, permissions) as
an Elixir DSL; Caravela generates Ecto schemas, migrations, Phoenix
contexts, JSON controllers, Absinthe schemas, and a Svelte frontend
layer that works under both LiveView's WebSocket transport and an
Inertia-style HTTP transport - per entity, via `frontend: :live` or
`frontend: :rest`.

```elixir
defmodule MyApp.Domains.Library do
  use Caravela.Domain, multi_tenant: true

  version "v1"

  entity :books, frontend: :rest do
    field :title, :string, required: true, min_length: 3
    field :published, :boolean, default: false
  end

  entity :authors do
    field :name, :string, required: true
  end

  policy :books do
    allow :create, fn actor -> actor.role in [:admin, :editor] end
  end
end
```

```bash
mix caravela.gen MyApp.Domains.Library
mix caravela.gen.live MyApp.Domains.Library
```

## Install

```elixir
{:caravela, "~> 0.13"},
{:caravela_svelte, "~> 0.1"}  # required for mix caravela.gen.live output
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
- [Svelte frontend (render modes)](docs/livesvelte.md)
- [Live runtime (`Caravela.Live.*`)](docs/live_runtime.md)
- [Flows - async workflow orchestration](docs/flows.md)
- [Regeneration & the CUSTOM marker](docs/regeneration.md)
- [Authentication (`authenticatable`)](docs/auth.md)
- [Policies - triple-target authorization](docs/policies.md)
- [Validation - structured errors + gettext](docs/validation.md)
- [Testing Caravela](docs/testing.md)
- [MCP server - Caravela as an LLM tool surface](docs/mcp.md)

Run `mix docs` to build the full API reference locally (HexDocs-style).

## License

MPL-2.0 - see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Use Caravela freely, including in closed-source apps. Modifications to
Caravela source files must stay under MPL-2.0 with attribution.

## Support the project

Caravela is built in the open and free to use. Donation channels will
be linked here once set up. PRs, bug reports, and kind words all help
keep the sails full.
