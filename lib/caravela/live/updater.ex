defmodule Caravela.Live.Updater do
  @moduledoc """
  Composable state updater functions for LiveView assigns.

  An updater is a pure function from one assigns-map to another, or a
  function of arity 2 that takes an extra argument (an "event payload").
  The point is to make state transitions composable and testable in
  isolation — any LiveView `handle_event` can be reassembled from small
  named updaters rather than inlining the logic.

  When the composed updater is applied via `apply/3` to a socket, the
  LiveView calls `assign/2` with the returned map, and LiveSvelte pushes
  the resulting prop diff to the Svelte component.

  ### Quick example

      import Caravela.Live.Updater

      mark_saving = fn assigns -> %{assigns | saving: true} end
      clear_flash = fn assigns -> %{assigns | flash_message: nil} end

      combined = mark_saving ~> clear_flash
      combined.(%{saving: false, flash_message: "old"})
      #=> %{saving: true, flash_message: nil}

  The `~>` operator is sugar for `compose/2` and can chain any number of
  updaters into a single function.
  """

  @type assigns :: map()
  @type updater :: (assigns() -> assigns()) | (assigns(), any() -> assigns())

  @doc """
  Compose two updaters: apply `a`, then apply `b` to the result.

  If either side takes two arguments (an event payload), use `apply/3`
  with the payload threaded explicitly. `compose/2` itself only composes
  the 1-arity shape — keep 2-arity updaters at the call boundary.
  """
  @spec compose(updater(), updater()) :: (assigns() -> assigns())
  def compose(a, b) when is_function(a, 1) and is_function(b, 1) do
    fn assigns -> assigns |> a.() |> b.() end
  end

  @doc """
  Narrow an updater so it operates on one nested key of the assigns
  map, leaving every other key untouched. Useful when a parent LiveView
  embeds child-domain state under a namespaced key.

      increment = fn %{counter: n} = s -> %{s | counter: n + 1} end

      scoped = Caravela.Live.Updater.embed(increment, :child_state)
      scoped.(%{child_state: %{counter: 0}, other: :untouched})
      #=> %{child_state: %{counter: 1}, other: :untouched}
  """
  @spec embed(updater(), atom()) :: (assigns() -> assigns())
  def embed(updater, key) when is_function(updater, 1) and is_atom(key) do
    fn assigns -> Map.update!(assigns, key, updater) end
  end

  @doc """
  Apply an updater to a LiveView socket, assigning the returned map.

  Accepts both arities: `run(socket, u)` for `(assigns -> assigns)`,
  and `run(socket, u, arg)` for `(assigns, arg -> assigns)`. The
  result replaces `socket.assigns`, which means LiveSvelte re-renders
  the Svelte component with the new props.

  For real `Phoenix.LiveView.Socket` structs we route through
  `Phoenix.Component.assign/2` so LiveView change-tracking fires. For
  plain-map sockets (used in tests / tooling) we replace `:assigns`
  directly. That keeps `Caravela.Live.Updater` unit-testable without a
  live LiveView process.
  """
  @spec run(map(), updater()) :: map()
  def run(%{assigns: assigns} = socket, updater) when is_function(updater, 1) do
    assign_all(socket, updater.(assigns))
  end

  @spec run(map(), updater(), any()) :: map()
  def run(%{assigns: assigns} = socket, updater, arg) when is_function(updater, 2) do
    assign_all(socket, updater.(assigns, arg))
  end

  # Backwards-compat alias. `apply/2,3` shadows `Kernel.apply/2,3` in
  # pipelines and readers' mental models, which is why `run/2,3` is the
  # preferred name. The aliases are kept so early adopters calling
  # `Caravela.Live.Updater.apply(...)` still work, but are undocumented
  # and will be removed in a future major release.
  @doc false
  def apply(socket, updater), do: run(socket, updater)
  @doc false
  def apply(socket, updater, arg), do: run(socket, updater, arg)

  # Replace socket.assigns. For real LiveView sockets we route through
  # `Phoenix.Component.assign/2` so LiveView's change tracking fires
  # (required for LiveSvelte's prop diffing). For plain-map sockets
  # (tests, tooling), fall back to direct replacement — keeps the
  # Updater testable without a running LiveView.
  defp assign_all(%{assigns: _} = socket, new_assigns) when is_map(new_assigns) do
    if is_struct(socket) and Code.ensure_loaded?(Phoenix.LiveView.Socket) and
         socket.__struct__ == Phoenix.LiveView.Socket do
      Phoenix.Component.assign(socket, new_assigns)
    else
      %{socket | assigns: new_assigns}
    end
  end

  @doc """
  Pipe operator for chaining updaters: `u ~> v` is equivalent to
  `compose(u, v)`. Left-associative, so `a ~> b ~> c` composes as
  `compose(compose(a, b), c)`.

      import Caravela.Live.Updater

      pipeline = updater_a ~> updater_b ~> updater_c
      pipeline.(assigns)
  """
  defmacro a ~> b do
    quote do
      Caravela.Live.Updater.compose(unquote(a), unquote(b))
    end
  end
end
