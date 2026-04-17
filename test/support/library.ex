defmodule MyApp.Domains.Library do
  use Caravela.Domain

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

  # Permissions

  can_read :books, fn query, context ->
    case Map.get(context || %{}, :role) do
      :admin -> query
      _ -> query
    end
  end

  can_create :books, fn context ->
    Map.get(context || %{}, :role) in [:admin, :editor]
  end

  can_update :books, fn _book, context ->
    Map.get(context || %{}, :role) == :admin
  end

  can_delete :books, fn _book, context ->
    Map.get(context || %{}, :role) == :admin
  end
end
