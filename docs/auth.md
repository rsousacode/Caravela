# Authentication (`authenticatable`)

Caravela treats authentication as a **trait** on a domain entity, not a
separate library. Declare the `authenticatable` block on your user
entity; the compiler extends the IR with the credential fields your
strategies need, and `mix caravela.gen.auth` emits the full auth stack:
a context module, a session schema, Plug pipelines, LiveView `on_mount`
hooks, an HTTP controller, and a session-tokens migration.

The generated code is standard Phoenix. You can edit it, eject it, or
let Caravela regenerate it — user-authored code below the
`# --- CUSTOM ---` marker is preserved on every rerun.

## DSL

```elixir
defmodule MyApp.Domains.Identity do
  use Caravela.Domain, multi_tenant: true

  version "v1"

  entity :users do
    field :email, :string, required: true, unique: true
    field :name, :string, required: true
    field :role, :string, default: "viewer"

    authenticatable do
      strategy :password

      strategy :api_token,
        scopes: [:read, :write, :admin],
        ttl: {90, :days},
        max_tokens: 5

      session :token,
        ttl: {30, :days},
        remember_me: {365, :days},
        max_sessions: 5

      confirm :email, token_ttl: {24, :hours}
      reset :password, token_ttl: {1, :hour}

      on_register fn changeset, _context -> changeset end

      on_login fn user, _context ->
        if user.suspended, do: {:error, :suspended}, else: :ok
      end
    end
  end
end
```

### Strategies

| Strategy     | Effect                                                                 |
|--------------|------------------------------------------------------------------------|
| `:password`  | Email + Argon2-hashed password. Requires an `:email` field on the entity. Injects `hashed_password`. |
| `:api_token` | Bearer tokens with scope + expiry. Injects `api_tokens` (map).         |

### Lifecycle options

- `session :token, ttl: {n, :days}, remember_me: {n, :days}, max_sessions: n`
- `confirm :email, token_ttl: {n, :hours}` — injects `confirmed_at`;
  unconfirmed users cannot log in.
- `reset :password, token_ttl: {n, :hours}` — enables reset flow.
- `on_register fn changeset, ctx -> changeset end`
- `on_login fn user, ctx -> :ok | {:error, term} end`

### Compile-time validations

- Exactly one entity per domain may be `authenticatable`.
- `strategy :password` requires an `:email` field.
- You may not manually declare `:hashed_password`, `:confirmed_at`, or
  `:api_tokens`; they are auto-injected.

## Generate

```bash
mix caravela.gen.auth MyApp.Domains.Identity
```

Emits (for a domain with `version "v1"`):

```
# Server (Phase 7)
lib/my_app/identity/v1/auth.ex              # context (register/login/logout/…)
lib/my_app/identity/v1/user_session.ex      # session schema
lib/my_app_web/plugs/auth.ex                # Plug pipeline
lib/my_app_web/live/auth_hooks.ex           # LiveView on_mount hooks
lib/my_app_web/controllers/v1/auth_controller.ex
priv/repo/migrations/<ts>_create_identity_user_sessions.exs

# UI (Phase 8)
assets/svelte/v1/auth/LoginForm.svelte
assets/svelte/v1/auth/RegisterForm.svelte      # fields synthesised from the entity
assets/svelte/v1/auth/ResetPasswordForm.svelte  # two-phase: request + confirm
assets/svelte/v1/auth/ConfirmEmail.svelte
assets/svelte/v1/auth/TokenManager.svelte       # only with strategy :api_token
assets/svelte/v1/auth/SessionList.svelte
lib/my_app_web/live/v1/auth_live/*.ex           # matching LiveView pages
```

A router snippet (public auth routes, authenticated `live_session`,
authenticated API) is printed to stdout — paste it into your router.

Flags: `--dry-run`, `--output DIR`, `--force`, `--skip-ui` (server only),
`--skip-router` (suppress the snippet).

## Wire it up

Add to your router:

```elixir
import MyAppWeb.Plugs.Auth

pipeline :api do
  plug :accepts, ["json"]
  plug :fetch_current_user
end

pipeline :require_auth do
  plug :require_auth
end

scope "/api/v1", MyAppWeb.V1 do
  pipe_through :api

  post "/auth/register", AuthController, :register
  post "/auth/login",    AuthController, :login
  delete "/auth/logout", AuthController, :logout

  pipe_through :require_auth
  # protected routes
end
```

LiveView hook:

```elixir
live_session :protected, on_mount: [{MyAppWeb.Live.AuthHooks, :require_auth}] do
  live "/dashboard", DashboardLive
end
```

## Dependencies

Password hashing uses `:argon2_elixir`. Add it to your deps — the
Caravela package does not pull it in:

```elixir
{:argon2_elixir, "~> 4.0"}
```

## Svelte components

Every generated component is Svelte 5 (`$props`, `$state`, `$derived`)
and receives `live: LiveHandle` — the same prop every Caravela-generated
component gets — so events flow through `live.pushEvent(...)`.

### `RegisterForm.svelte`

Form fields are synthesised from the authenticatable entity: every
public, non-`auth`, non-`role`, non-`tenant_id` field gets an input.
Add `field :company, :string, required: true` to the entity and
regenerate — the registration form grows a required company input on
the next run. Fields with a `default:` (like `role`) are omitted so the
server picks the value.

### `TokenManager.svelte`

Rendered only when `strategy :api_token` is declared. The scope `<select>`
is typed from the configured scopes (e.g. `'read' | 'write' | 'admin'`)
and a `MAX_TOKENS` constant reflects `max_tokens:`. Create/revoke
dispatch `create_token` / `revoke_token` events.

### `SessionList.svelte`

Lists the active session rows returned by `Auth.list_sessions/2`. The
"current" session (the one backing the visit) is flagged and cannot be
self-revoked; a "sign out other sessions" button batches the rest.

## `CurrentUser` as a typed Svelte prop

When the domain is authenticated, the TypeScript interfaces file adds:

```ts
export type CurrentUser = User | null;
export interface ApiToken { id: string; scope: 'read' | 'write' | 'admin'; … }
export interface Session  { id: string; is_current: boolean; … }
```

`User` is the entity interface with **credential fields stripped**:
`hashed_password` and `api_tokens` never cross the wire. `confirmed_at`
is kept so the UI can gate features on email confirmation.

## Router snippet

Every `mix caravela.gen.auth` run prints a ready-to-paste snippet
containing:

- Public auth routes: `/auth/login`, `/auth/register`,
  `/auth/reset-password`, `/auth/reset-password/:token`,
  `/auth/confirm/:token`
- A matching `/api/auth/{register,login,logout}` scope for non-browser
  clients
- A `live_session :authenticated` with `on_mount: [{…AuthHooks, :require_auth}]`
  — every LiveView mounted inside it receives `current_user` as a typed
  Svelte prop
- An authenticated API scope accepting either session cookie or
  `Authorization: Bearer <token>`

## Multi-tenancy

With `multi_tenant: true`, the context scopes email lookups by
`tenant_id` (from `context.tenant_id`) and stamps every registration
with the caller's tenant. `fetch_current_user` does not set
`tenant_id` itself — your app sets it earlier in the pipeline (e.g.
from a subdomain plug or `X-Tenant-Id` header).
