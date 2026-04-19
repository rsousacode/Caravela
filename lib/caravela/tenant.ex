defmodule Caravela.Tenant do
  @moduledoc """
  Row-level multi-tenancy support.

  When a domain is declared with `use Caravela.Domain, multi_tenant: true`,
  the compiler calls `inject/1` on the IR to add a `tenant_id` field
  (`:binary_id`, required) to every entity. The generated context module
  then uses `scope_tenant/2` and `inject_tenant_id/2` helpers to scope
  every read by `tenant_id` and stamp every write with the caller's
  tenant id.

  This module only produces IR updates — the actual scoping helpers
  live in the context template (see `priv/templates/context.eex`).
  """

  alias Caravela.Schema.{Domain, Entity, Field}

  @doc "The DSL name of the injected tenant field."
  @spec field_name() :: :tenant_id
  def field_name, do: :tenant_id

  @doc """
  Add a `tenant_id` field to every entity in the domain when
  `multi_tenant: true` is enabled. A no-op otherwise.
  """
  @spec inject(Domain.t()) :: Domain.t()
  def inject(%Domain{} = domain) do
    if Domain.multi_tenant?(domain) do
      %Domain{domain | entities: Enum.map(domain.entities, &inject_entity/1)}
    else
      domain
    end
  end

  @doc "Returns `true` if the given field was auto-injected by `Caravela.Tenant`."
  @spec injected?(Field.t()) :: boolean()
  def injected?(%Field{opts: opts}) do
    Keyword.get(opts || [], :tenant, false) == true
  end

  # --- Internal --------------------------------------------------------------

  defp inject_entity(%Entity{fields: fields} = entity) do
    tenant = %Field{
      name: field_name(),
      type: :binary_id,
      opts: [required: true, tenant: true]
    }

    %Entity{entity | fields: [tenant | fields]}
  end
end
