defmodule MyApp.Domains.Library do
  # This fixture predates `default_policy: :deny` — keep the legacy
  # permissive fallback so the generic CRUD tests (which don't declare
  # policies on every entity) still list/create records freely.
  use Caravela.Domain, default_policy: :allow

  entity :authors do
    field :name, :string, required: true
    field :bio, :text
    field :born, :date
  end

  entity :books do
    field :title, :string, required: true, min_length: 3
    field :isbn, :string, format: ~r/^\d{13}$/
    field :published, :boolean, default: false
    field :price, :decimal, precision: 10, scale: 2
  end

  entity :publishers do
    field :name, :string, required: true
    field :country, :string
  end

  relation :authors, :books, type: :has_many
  relation :books, :publishers, type: :belongs_to

  # Hooks

  on_create :books, fn changeset, _context ->
    # Mark whether we saw the changeset at create time by tagging in
    # metadata — the test introspects this via fallback behaviour.
    changeset
  end

  on_update :books, fn changeset, _context ->
    changeset
  end

  on_delete :authors, fn _author, context ->
    if Map.get(context || %{}, :has_published_books, false) do
      {:error, :has_published_books}
    else
      :ok
    end
  end

  # Policies (the authorization model — replaces the legacy
  # `can_read` / `can_create` / `can_update` / `can_delete` hooks).

  policy :books do
    scope fn query, _actor -> query end

    allow :create, fn actor -> Map.get(actor || %{}, :role) in [:admin, :editor] end
    allow :update, fn actor, _record -> Map.get(actor || %{}, :role) == :admin end
    allow :delete, fn actor, _record -> Map.get(actor || %{}, :role) == :admin end
  end
end
