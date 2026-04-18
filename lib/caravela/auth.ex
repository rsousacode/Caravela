defmodule Caravela.Auth do
  @moduledoc """
  Trait-based authentication support.

  When an entity declares an `authenticatable` block, the compiler
  invokes `inject/1` on the IR to add credential-storage fields
  (`hashed_password`, `confirmed_at`, `api_tokens`) alongside the
  entity's explicit fields. The generators in `Caravela.Gen.Auth`
  consume those fields like any other.

  This module only transforms the IR — the actual auth context,
  plugs, LiveView hooks, controller, and session schema live in the
  templates under `priv/templates/auth_*.eex`.
  """

  alias Caravela.Schema.{AuthConfig, Domain, Entity, Field}

  @doc "Name of the generated session schema module suffix."
  def session_module_suffix, do: :UserSession

  @doc """
  Extend every authenticatable entity with the hidden credential fields
  required by its declared strategies. A no-op for non-authenticatable
  domains.
  """
  def inject(%Domain{} = domain) do
    %Domain{domain | entities: Enum.map(domain.entities, &inject_entity/1)}
  end

  defp inject_entity(%Entity{auth: nil} = entity), do: entity

  defp inject_entity(%Entity{auth: %AuthConfig{} = cfg, fields: fields} = entity) do
    extras =
      []
      |> maybe_add(AuthConfig.password?(cfg), password_field())
      |> maybe_add(AuthConfig.confirm?(cfg), confirmed_at_field())
      |> maybe_add(AuthConfig.api_token?(cfg), api_tokens_field())

    # Inject after the user's declared fields so generated migrations
    # and schemas list explicit fields first, credential fields last.
    %Entity{entity | fields: fields ++ Enum.reverse(extras)}
  end

  defp maybe_add(acc, false, _field), do: acc
  defp maybe_add(acc, true, field), do: [field | acc]

  defp password_field do
    %Field{
      name: :hashed_password,
      type: :string,
      opts: [auth: :password, redact: true]
    }
  end

  defp confirmed_at_field do
    %Field{
      name: :confirmed_at,
      type: :utc_datetime,
      opts: [auth: :confirm]
    }
  end

  defp api_tokens_field do
    %Field{
      name: :api_tokens,
      type: :map,
      opts: [auth: :api_token, default: %{}]
    }
  end

  @doc "Returns `true` if the given field was auto-injected by `Caravela.Auth`."
  def injected?(%Field{opts: opts}) do
    Keyword.has_key?(opts || [], :auth)
  end
end
