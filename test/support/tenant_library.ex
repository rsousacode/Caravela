defmodule MyApp.Domains.TenantLibrary do
  @moduledoc """
  Test-only domain exercising Phase 3 features: `multi_tenant: true`
  and `version "v1"`. Kept separate from `MyApp.Domains.Library` so the
  Phase 1/2 tests continue to exercise a plain single-tenant domain.
  """

  use Caravela.Domain, multi_tenant: true

  version "v1"

  entity :authors do
    field :name, :string, required: true
    field :bio, :text
  end

  entity :books do
    field :title, :string, required: true, min_length: 3
    field :published, :boolean, default: false
  end

  relation :authors, :books, type: :has_many

  on_create :books, fn changeset, _context -> changeset end

  can_read :books, fn query, _context -> query end
end
