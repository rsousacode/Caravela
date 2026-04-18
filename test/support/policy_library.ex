defmodule MyApp.Domains.PolicyLibrary do
  @moduledoc """
  Test-only domain exercising Phase 9 triple-target policies, including
  the new deny-by-default fallback (no `default_policy` option set here
  → `:deny`). The `:widgets` entity has no `policy` block to exercise
  that fallback path.
  """

  use Caravela.Domain

  entity :books do
    field :title, :string, required: true
    field :isbn, :string
    field :published, :boolean, default: false
    field :price, :decimal, precision: 10, scale: 2
    field :internal_notes, :text
    field :cost_basis, :decimal, precision: 10, scale: 2
    field :author_email, :string
  end

  entity :authors do
    field :name, :string, required: true
    field :email, :string, required: true
  end

  entity :widgets do
    # Intentionally no `policy` block — under `default_policy: :deny`
    # every rule falls through to the deny fallback.
    field :name, :string, required: true
  end

  relation :authors, :books, type: :has_many

  policy :books do
    scope fn query, actor ->
      case actor.role do
        :admin -> query
        _ -> where(query, [b], b.published == true)
      end
    end

    field :price, visible: fn actor -> actor.role in [:admin, :editor] end
    field :internal_notes, visible: fn actor -> actor.role == :admin end
    field :cost_basis, visible: fn actor -> actor.role == :admin end

    field :author_email,
      visible: fn actor, record ->
        actor.role == :admin or actor.id == Map.get(record, :author_id)
      end

    allow :create, fn actor -> actor.role in [:admin, :editor] end

    allow :update, fn actor, record ->
      actor.role == :admin or actor.id == Map.get(record, :author_id)
    end

    allow :delete, fn actor -> actor.role == :admin end
  end

  policy :authors do
    field :email, visible: fn actor -> actor.role == :admin end
  end
end
