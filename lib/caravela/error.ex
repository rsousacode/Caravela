defmodule Caravela.Error do
  @moduledoc """
  Uniform error shape emitted by every Caravela read / write path.

  Context functions and generated LiveViews can return any of four
  `{:error, reason}` shapes today:

      {:error, :unauthorized}
      {:error, :not_found}
      {:error, %Ecto.Changeset{}}
      {:error, other}

  …and every handler has to match on all four. `Caravela.Error`
  collapses them into one struct so upstream code (a LiveView event
  handler, a JSON-API controller, a telemetry reporter) can pattern
  match once and discriminate by `:kind`:

      case MyApp.Library.create_book(attrs, context) do
        {:ok, book} ->
          ...

        {:error, %Caravela.Error{kind: :unauthorized}} ->
          ...

        {:error, %Caravela.Error{kind: :invalid, details: changeset}} ->
          ...
      end

  ## Kinds

    * `:unauthorized` — a policy rule (scope, field, or allow) denied
      the request. `details` is the entity atom that failed the check.
    * `:not_found` — a `get_*` / `delete_*(id, _)` lookup returned nil
      (either missing or hidden by a policy scope). `details` is the id.
    * `:invalid` — input failed changeset validation. `details` is
      the `%Ecto.Changeset{}`.
    * `:internal` — anything else: a raised exception, a hook that
      returned a non-`:ok` tuple, a downstream integration failure.
      `details` is the original reason term.

  The generated contexts continue to emit the plain atoms / changesets
  for backwards compatibility. Use `wrap/1` to lift an existing error
  into the struct form when routing through a boundary that prefers
  the uniform shape.
  """

  @enforce_keys [:kind]
  defstruct [:kind, :details]

  @type kind :: :unauthorized | :not_found | :invalid | :internal

  @type t :: %__MODULE__{
          kind: kind(),
          details: term()
        }

  @doc """
  Lift a "plain" error reason into a `%Caravela.Error{}` struct.

      iex> Caravela.Error.wrap(:unauthorized)
      %Caravela.Error{kind: :unauthorized, details: nil}

      iex> Caravela.Error.wrap(%Ecto.Changeset{})
      %Caravela.Error{kind: :invalid, details: %Ecto.Changeset{}}

  Accepts the raw error term *or* an `{:error, reason}` tuple. Already-
  wrapped `%Caravela.Error{}` values pass through unchanged.
  """
  @spec wrap(term()) :: t()
  def wrap({:error, reason}), do: wrap(reason)
  def wrap(%__MODULE__{} = err), do: err
  def wrap(:unauthorized), do: %__MODULE__{kind: :unauthorized}
  def wrap(:not_found), do: %__MODULE__{kind: :not_found}

  def wrap(%{__struct__: Ecto.Changeset} = cs) do
    %__MODULE__{kind: :invalid, details: cs}
  end

  def wrap(other), do: %__MODULE__{kind: :internal, details: other}

  @doc """
  Short human-friendly string describing the error. Handy as a default
  flash message when a LiveView doesn't care about the discrimination.
  """
  @spec message(t()) :: String.t()
  def message(%__MODULE__{kind: :unauthorized}), do: "Not authorized"
  def message(%__MODULE__{kind: :not_found}), do: "Not found"
  def message(%__MODULE__{kind: :invalid}), do: "Invalid"
  def message(%__MODULE__{kind: :internal, details: d}), do: "Error: " <> inspect(d)
end
