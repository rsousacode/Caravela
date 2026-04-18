defmodule MyApp.Domains.Identity do
  @moduledoc """
  Test-only domain exercising Phase 7 authentication features:
  a `:users` entity with password + api_token strategies, session
  config, confirm/reset, and both `on_register` / `on_login` hooks.
  """

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
        max_tokens: 3

      session :token,
        ttl: {30, :days},
        remember_me: {365, :days},
        max_sessions: 5

      confirm :email, token_ttl: {24, :hours}
      reset :password, token_ttl: {1, :hour}

      on_register fn changeset, _context -> changeset end

      on_login fn user, _context ->
        if Map.get(user, :suspended, false), do: {:error, :suspended}, else: :ok
      end
    end
  end
end
