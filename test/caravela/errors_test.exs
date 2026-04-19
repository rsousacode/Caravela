defmodule Caravela.ErrorsTest do
  use ExUnit.Case, async: true

  alias Caravela.{DSLError, GenError, Errors}

  describe "DSLError formatting" do
    test "renders a four-part block with all fields" do
      err =
        %DSLError{
          message: "`field :title` is missing a type",
          snippet: "field :title",
          suggestion: "field :title, :string, required: true",
          docs_url: "https://hexdocs.pm/caravela/dsl.html#fields"
        }

      msg = Exception.message(err)

      assert msg =~ "Caravela.DSLError"
      assert msg =~ "`field :title` is missing a type"
      assert msg =~ "Got:"
      assert msg =~ "field :title"
      assert msg =~ "Suggestion:"
      assert msg =~ "field :title, :string, required: true"
      assert msg =~ "See:"
      assert msg =~ "hexdocs.pm/caravela/dsl.html#fields"
    end

    test "omits the Got section when snippet is nil" do
      err = %DSLError{message: "bad", suggestion: "fix it"}
      msg = Exception.message(err)

      refute msg =~ "Got:"
      assert msg =~ "Suggestion:"
    end

    test "omits the Suggestion section when nil" do
      err = %DSLError{message: "bad", snippet: "what we got"}
      msg = Exception.message(err)

      assert msg =~ "Got:"
      refute msg =~ "Suggestion:"
    end

    test "omits the See: line when docs_url is nil" do
      err = %DSLError{message: "bad"}
      msg = Exception.message(err)

      refute msg =~ "See:"
    end

    test "multi-line snippet is indented consistently" do
      err = %DSLError{
        message: "bad",
        snippet: "line one\nline two\nline three"
      }

      msg = Exception.message(err)

      for line <- ["line one", "line two", "line three"] do
        assert msg =~ "       " <> line,
               "expected #{inspect(line)} to be indented (got: #{inspect(msg)})"
      end
    end
  end

  describe "GenError formatting" do
    test "renders the same four-part shape" do
      err = %GenError{
        message: "context references an unknown entity",
        snippet: "alias MyApp.Library.Ghost",
        suggestion: "declare entity :ghosts, or remove the alias"
      }

      msg = Exception.message(err)
      assert msg =~ "Caravela.GenError"
      assert msg =~ "context references an unknown entity"
      assert msg =~ "Got:"
      assert msg =~ "Suggestion:"
    end
  end

  describe "Errors.dsl/2" do
    test "builds a DSLError from a list of fields" do
      err =
        Errors.dsl(nil,
          message: "oops",
          suggestion: "do this"
        )

      assert %DSLError{message: "oops", suggestion: "do this"} = err
    end

    test "raising the returned struct works as expected" do
      assert_raise DSLError, ~r/oops/, fn ->
        raise Errors.dsl(nil, message: "oops", suggestion: "do this")
      end
    end

    test "prefers an explicit :snippet over auto-extracted from env" do
      err =
        Errors.dsl(nil,
          message: "m",
          snippet: "explicit_snippet",
          suggestion: "s"
        )

      assert err.snippet == "explicit_snippet"
    end
  end

  describe "Errors.gen/1" do
    test "builds a GenError" do
      err = Errors.gen(message: "generator blew up", suggestion: "fix domain")
      assert %GenError{message: "generator blew up"} = err
    end
  end

  describe "snippet_from_env/1" do
    setup do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "caravela_errors_test_#{System.unique_integer([:positive])}.ex"
        )

      File.write!(tmp, """
      defmodule Foo do
        def a, do: :ok
        def b, do: :ok
        def c, do: :ok
      end
      """)

      on_exit(fn -> File.rm(tmp) end)
      {:ok, path: tmp}
    end

    test "reads the focus line + one line above/below", %{path: file} do
      env = %Macro.Env{file: file, line: 3}
      snippet = Errors.snippet_from_env(env)

      assert snippet =~ "def a, do: :ok"
      assert snippet =~ "def b, do: :ok"
      assert snippet =~ "def c, do: :ok"
      # Focus marker ">>>" on the target line.
      assert snippet =~ ~r/>>>.*def b/
      # Relative-to-cwd footer with line number.
      assert snippet =~ ~r/# at .+:3$/
    end

    test "returns nil when the file cannot be read" do
      env = %Macro.Env{file: "/no/such/file.ex", line: 1}
      assert Errors.snippet_from_env(env) == nil
    end

    test "returns nil for a nil env" do
      assert Errors.snippet_from_env(nil) == nil
    end
  end
end
