defmodule Caravela.Live.OnMount do
  @moduledoc """
  `on_mount` callback that assembles the per-request context map the
  generated Caravela contexts expect (`%{current_user: ..., tenant: ...}`)
  and assigns it to `socket.assigns.context`.

  Every generated LiveView currently re-rolls its own `build_context/1`
  and threads `context` through each context call. Plugging this
  on_mount in lets the whole LiveView read from `@context` instead:

      defmodule MyAppWeb.Library.BookLive.Index do
        use MyAppWeb, :live_view
        on_mount Caravela.Live.OnMount

        def mount(_params, _session, socket) do
          {:ok, assign(socket, :books, MyApp.Library.list_books(socket.assigns.context))}
        end
      end

  Keys pulled from `socket.assigns`:

    * `:current_user` — always included when present, otherwise `nil`.
    * `:tenant` — included when present. Mirrors the generated
      `build_context/1` shape for multi-tenant domains.

  Extra keys can be folded in by calling `put/3` from your own
  `on_mount` callback (defined after this one), or by setting extra
  assigns on the socket before this hook runs.
  """

  @doc """
  `Phoenix.LiveView` on_mount hook. Wires `:current_user` and `:tenant`
  from the socket into the `:context` assign. Always returns `{:cont,
  socket}` — it never blocks a mount.
  """
  def on_mount(:default, _params, _session, socket) do
    {:cont, assign_context(socket, build_context(socket))}
  end

  @doc """
  Merge `overrides` into the context map currently on `socket`. Useful
  from a follow-up `on_mount` to stamp values this hook doesn't know
  about (api keys, request ids, feature-flag snapshots, …).

      on_mount {Caravela.Live.OnMount, :default}
      on_mount fn _, _, _, socket ->
        {:cont, Caravela.Live.OnMount.put(socket, :request_id, Logger.metadata()[:request_id])}
      end
  """
  def put(%{assigns: %{context: ctx}} = socket, key, value) when is_map(ctx) do
    assign_context(socket, Map.put(ctx, key, value))
  end

  def put(%{assigns: _} = socket, key, value) do
    assign_context(socket, %{key => value})
  end

  defp build_context(%{assigns: assigns}) do
    %{current_user: Map.get(assigns, :current_user)}
    |> maybe_put_tenant(assigns)
  end

  defp maybe_put_tenant(ctx, %{tenant: tenant}) when not is_nil(tenant) do
    Map.put(ctx, :tenant, tenant)
  end

  defp maybe_put_tenant(ctx, _assigns), do: ctx

  defp assign_context(socket, ctx) do
    if is_struct(socket) and Code.ensure_loaded?(Phoenix.LiveView.Socket) and
         socket.__struct__ == Phoenix.LiveView.Socket do
      Phoenix.Component.assign(socket, :context, ctx)
    else
      %{socket | assigns: Map.put(socket.assigns, :context, ctx)}
    end
  end
end
