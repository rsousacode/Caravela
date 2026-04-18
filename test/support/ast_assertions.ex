defmodule Caravela.ASTAssertions do
  @moduledoc """
  AST-based assertions for tests that inspect generated Elixir source.

  String matching on generated code is brittle: a formatter change,
  a line wrap, or an extra import rewrites every substring assertion.
  These helpers parse the source and walk the AST looking for the
  specific structural features we care about, so tests stay immune
  to cosmetic changes.

  ## Usage

      use ExUnit.Case
      import Caravela.ASTAssertions

      test "list_books pipes through apply_scope" do
        {_path, src} = Caravela.Gen.Context.render(domain)

        # Matches regardless of line wrap or argument formatting.
        assert_calls src, :apply_scope, [:books, :_]
        assert_def src, :list_books, 1
      end

  Keep these assertions structural. If you find yourself wanting to
  assert the exact shape of a complex AST subtree, prefer Tier 2
  (compile the source and exercise it).
  """

  import ExUnit.Assertions

  @doc """
  Asserts that the Elixir source in `code` contains a call to
  `function/arity`. When `module` is `nil`, matches any unqualified
  call to that name; otherwise matches `Module.function(...)` remote
  calls where the trailing segment of the alias equals `module`.

  `args_match` is a list of argument matchers, applied positionally:

    * `:_`          — matches anything
    * an atom       — matches that literal atom
    * a string      — matches that literal string
    * any other term — compared with `==`

  Returns `:ok`; raises `ExUnit.AssertionError` on mismatch.

      assert_calls(src, :apply_scope, [:books, :_])
      assert_calls(src, :__caravela_policy_field_visible__, [:books, :price, :_], module: SomeDomain)
  """
  def assert_calls(code, function, args_match, opts \\ [])
      when is_binary(code) and is_atom(function) and is_list(args_match) do
    module = Keyword.get(opts, :module)
    ast = parse!(code)
    arity = length(args_match)

    found? =
      ast
      |> reduce(false, fn
        # Remote call: Mod.Sub.function(args)
        {{:., _, [{:__aliases__, _, aliases}, name]}, _, args}, acc
        when name == function ->
          acc or
            (length(args) == arity and
               match_module?(aliases, module) and
               match_args?(args, args_match))

        # Local call: function(args)
        {name, _, args}, acc
        when is_atom(name) and name == function and is_list(args) and module == nil ->
          acc or (length(args) == arity and match_args?(args, args_match))

        _node, acc ->
          acc
      end)

    assert found?,
           "expected #{describe_call(module, function, arity)} in generated source but did not find it"
  end

  @doc """
  Asserts a `def` (public or private) with `name/arity` exists in
  `code`. Default-argument heads count toward the declared arity.

      assert_def src, :list_books, 1
      assert_def src, :delete_book, 2
  """
  def assert_def(code, name, arity)
      when is_binary(code) and is_atom(name) and is_integer(arity) do
    ast = parse!(code)

    found? =
      ast
      |> reduce(false, fn
        {kind, _, [{^name, _, args} | _]}, acc
        when kind in [:def, :defp] and is_list(args) ->
          acc or arity_matches?(args, arity)

        # `def name` with no args at all — body-less head like
        # `def foo(struct_or_id, context \\ %{})` arrives as args=nil
        # for the bodyless form in some shapes; accept if arity is 0.
        {kind, _, [{^name, _, nil} | _]}, acc
        when kind in [:def, :defp] ->
          acc or arity == 0

        _node, acc ->
          acc
      end)

    assert found?,
           "expected def #{name}/#{arity} in generated source but did not find it"
  end

  @doc """
  Asserts a module attribute assignment in the source. Useful for
  `@required_fields [...]` style output.

      assert_module_attr src, :required_fields, [:title]
  """
  def assert_module_attr(code, name, value) when is_binary(code) and is_atom(name) do
    ast = parse!(code)

    found? =
      ast
      |> reduce(false, fn
        {:@, _, [{^name, _, [literal]}]}, acc -> acc or literal == value
        _node, acc -> acc
      end)

    assert found?,
           "expected @#{name} #{inspect(value)} in generated source but did not find it"
  end

  # --- Internals ------------------------------------------------------------

  defp parse!(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} -> ast
      {:error, reason} -> raise "generated source did not parse: #{inspect(reason)}"
    end
  end

  # `Macro.prewalk/3`'s accumulator doesn't short-circuit; a fold over
  # the tree is cleaner for these read-only checks.
  defp reduce(ast, acc, fun) do
    {_ast, final} =
      Macro.prewalk(ast, acc, fn node, acc ->
        {node, fun.(node, acc)}
      end)

    final
  end

  # Match `aliases` ([A, B, C] from A.B.C) against `module`:
  #
  #   nil               — caller doesn't care (pure-function match still OK)
  #   atom              — match the LAST segment of the alias. The input
  #                       atom is a real module (`:"Elixir.Foo"`) so we
  #                       reduce it to its last segment before comparing.
  #   list of atoms     — match the full alias list
  defp match_module?(_aliases, nil), do: true

  defp match_module?(aliases, name) when is_atom(name) do
    short = name |> Module.split() |> List.last() |> String.to_atom()
    List.last(aliases) == short
  end

  defp match_module?(aliases, list) when is_list(list), do: aliases == list

  defp match_args?(args, matchers) do
    args
    |> Enum.zip(matchers)
    |> Enum.all?(fn {arg, match} -> match_arg?(arg, match) end)
  end

  defp match_arg?(_arg, :_), do: true
  defp match_arg?(arg, match) when is_atom(match), do: arg == match
  defp match_arg?(arg, match) when is_binary(match), do: arg == match
  defp match_arg?(arg, match), do: arg == match

  defp arity_matches?(args, expected) do
    # Default args (`x \\ foo`) appear as `{:\\, _, [var, default]}`.
    # They still count toward the declared arity of the head.
    length(args) == expected
  end

  defp describe_call(nil, function, arity), do: "#{function}/#{arity}"
  defp describe_call(module, function, arity), do: "#{inspect(module)}.#{function}/#{arity}"
end
