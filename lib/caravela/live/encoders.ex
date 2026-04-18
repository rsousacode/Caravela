defmodule Caravela.Live.Encoders do
  @moduledoc """
  Protocol implementations so Ecto/Decimal types survive the trip from
  the LiveView socket to a LiveSvelte Svelte component as sensible
  JSON values instead of struct dumps.

  Covers two structs that every generated CRUD page trips over:

    * `Decimal` — the Ecto `:decimal` type. Without a custom encoder,
      LiveSvelte's fallback serialises a `%Decimal{}` as
      `%{coef: _, exp: _, sign: _}`, which Svelte then stringifies as
      `[object Object]`. This impl emits the normalised decimal string
      (matching the generated TypeScript `string` type for `:decimal`
      fields).
    * `Ecto.Association.NotLoaded` — when a schema field is never
      preloaded, the default encoding leaks internal module names
      (`__owner__`, `__field__`) to the browser. This impl replaces
      the not-loaded sentinel with `nil`.

  The impls live under a `Code.ensure_loaded?/1` guard so the file is
  safe to compile even when LiveSvelte is absent or older than 0.18
  (where the `LiveSvelte.Encoder` protocol first landed).

  This module has no runtime API — it exists solely to host the two
  `defimpl` blocks below, which Elixir's protocol consolidation picks
  up automatically.
  """
end

if Code.ensure_loaded?(LiveSvelte.Encoder) do
  if Code.ensure_loaded?(Decimal) do
    defimpl LiveSvelte.Encoder, for: Decimal do
      def encode(decimal, _opts), do: Decimal.to_string(decimal, :normal)
    end
  end

  if Code.ensure_loaded?(Ecto.Association.NotLoaded) do
    defimpl LiveSvelte.Encoder, for: Ecto.Association.NotLoaded do
      def encode(_not_loaded, _opts), do: nil
    end
  end
end
