defmodule Caravela.SvelteAssertions do
  @moduledoc """
  Whitespace-insensitive substring assertions for generated Svelte /
  TypeScript source.

  Building a full TS/Svelte AST inside Elixir is overkill. Instead we
  collapse all whitespace runs (spaces, tabs, newlines) down to a
  single space on both the generated code and the expected fragment
  before comparing. That kills line-wrap and indentation brittleness
  while staying a one-liner to read.

      import Caravela.SvelteAssertions

      assert_contains(src, "let { books = [], live } = $props();")
      refute_contains(src, "hashed_password")

  If you need to assert *absence* of a token, use `refute_contains/2`
  - it also normalizes whitespace so a formatter break doesn't sneak
  the token past the refute.
  """

  import ExUnit.Assertions

  @doc "Asserts that `code` contains `fragment` (whitespace-insensitive)."
  def assert_contains(code, fragment) when is_binary(code) and is_binary(fragment) do
    if String.contains?(normalize(code), normalize(fragment)) do
      :ok
    else
      flunk("""
      expected to find (whitespace-insensitive):

          #{fragment}

      in generated source. Normalized source was:

      #{normalize(code) |> String.slice(0, 600)}#{if String.length(code) > 600, do: "…"}
      """)
    end
  end

  @doc "Refutes that `code` contains `fragment` (whitespace-insensitive)."
  def refute_contains(code, fragment) when is_binary(code) and is_binary(fragment) do
    unless String.contains?(normalize(code), normalize(fragment)) do
      :ok
    else
      flunk("expected NOT to find #{inspect(fragment)} but it appears in the generated source")
    end
  end

  @doc """
  Asserts that every fragment in `fragments` appears in `code`
  (whitespace-insensitive). Useful when a test wants to check a set
  of features without caring about order.
  """
  def assert_all_contain(code, fragments) when is_list(fragments) do
    Enum.each(fragments, &assert_contains(code, &1))
  end

  # Collapse every whitespace run to a single space and trim. We keep
  # the spaces (rather than stripping entirely) so tokens that happen
  # to sit next to each other don't falsely match a longer word.
  defp normalize(source) do
    source
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
