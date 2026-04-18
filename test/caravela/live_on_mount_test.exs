defmodule Caravela.LiveOnMountTest do
  @moduledoc """
  Unit tests for `Caravela.Live.OnMount`. The hook returns the tuple
  LiveView expects (`{:cont, socket}`) and builds a
  `%{current_user, tenant}` context map from the socket's assigns.
  """

  use ExUnit.Case, async: true

  alias Caravela.Live.OnMount

  defp socket(assigns) do
    # A plain map suffices — OnMount's assign_context helper falls back
    # to merging into `socket.assigns` when the value isn't a real
    # `Phoenix.LiveView.Socket` struct.
    %{assigns: assigns}
  end

  describe "on_mount/4" do
    test "assigns context with current_user when present" do
      user = %{id: 42}
      {:cont, socket} = OnMount.on_mount(:default, %{}, %{}, socket(%{current_user: user}))

      assert socket.assigns.context == %{current_user: user}
    end

    test "uses nil for current_user when absent" do
      {:cont, socket} = OnMount.on_mount(:default, %{}, %{}, socket(%{}))

      assert socket.assigns.context == %{current_user: nil}
    end

    test "includes :tenant when set on the socket" do
      tenant = %{id: "t1"}

      {:cont, socket} =
        OnMount.on_mount(
          :default,
          %{},
          %{},
          socket(%{current_user: nil, tenant: tenant})
        )

      assert socket.assigns.context == %{current_user: nil, tenant: tenant}
    end

    test "omits :tenant when nil" do
      {:cont, socket} =
        OnMount.on_mount(:default, %{}, %{}, socket(%{current_user: nil, tenant: nil}))

      refute Map.has_key?(socket.assigns.context, :tenant)
    end
  end

  describe "put/3" do
    test "merges into an existing context map" do
      starting = socket(%{context: %{current_user: nil}})

      merged = OnMount.put(starting, :request_id, "abc-123")

      assert merged.assigns.context == %{current_user: nil, request_id: "abc-123"}
    end

    test "creates the context map when missing" do
      starting = socket(%{})

      merged = OnMount.put(starting, :request_id, "abc-123")

      assert merged.assigns.context == %{request_id: "abc-123"}
    end
  end
end
