defmodule Caravela.ErrorTest do
  use ExUnit.Case, async: true

  alias Caravela.Error

  describe "wrap/1" do
    test "lifts :unauthorized to the struct form" do
      assert %Error{kind: :unauthorized, details: nil} = Error.wrap(:unauthorized)
    end

    test "lifts :not_found to the struct form" do
      assert %Error{kind: :not_found} = Error.wrap(:not_found)
    end

    test "lifts an Ecto.Changeset to {:invalid, changeset}" do
      cs = %Ecto.Changeset{}
      assert %Error{kind: :invalid, details: ^cs} = Error.wrap(cs)
    end

    test "falls through to :internal for unknown terms" do
      assert %Error{kind: :internal, details: :whoops} = Error.wrap(:whoops)
      assert %Error{kind: :internal, details: {1, 2}} = Error.wrap({1, 2})
    end

    test "unwraps {:error, reason} and recurses" do
      assert %Error{kind: :unauthorized} = Error.wrap({:error, :unauthorized})
      assert %Error{kind: :not_found} = Error.wrap({:error, :not_found})
      assert %Error{kind: :internal, details: :boom} = Error.wrap({:error, :boom})
    end

    test "passes through an already-wrapped struct" do
      err = %Error{kind: :invalid, details: :preset}
      assert Error.wrap(err) == err
    end
  end

  describe "message/1" do
    test "returns a short phrase per kind" do
      assert Error.message(%Error{kind: :unauthorized}) == "Not authorized"
      assert Error.message(%Error{kind: :not_found}) == "Not found"
      assert Error.message(%Error{kind: :invalid}) == "Invalid"

      assert Error.message(%Error{kind: :internal, details: :boom}) =~
               ~r/^Error:/
    end
  end
end
