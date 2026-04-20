defmodule Caravela.DSLError do
  @moduledoc """
  Raised from Caravela DSL macros when a caller uses them incorrectly.
  Carries a four-part message (what went wrong, what Caravela got, a
  suggested fix, a docs URL). See `Caravela.Errors` for helpers that
  build one of these from a `Macro.Env`.
  """
  defexception [:message, :snippet, :suggestion, :docs_url]

  @type t :: %__MODULE__{
          message: String.t(),
          snippet: String.t() | nil,
          suggestion: String.t() | nil,
          docs_url: String.t() | nil
        }

  @impl true
  def message(%__MODULE__{} = e) do
    Caravela.Errors.format(__MODULE__, %{
      message: e.message,
      snippet: e.snippet,
      suggestion: e.suggestion,
      docs_url: e.docs_url
    })
  end
end

defmodule Caravela.GenError do
  @moduledoc """
  Raised from `Caravela.Gen.*` functions and `mix caravela.gen.*`
  tasks when a generator can't produce a file given the current
  domain shape. Shares the four-part message shape with
  `Caravela.DSLError`.
  """
  defexception [:message, :snippet, :suggestion, :docs_url]

  @type t :: %__MODULE__{
          message: String.t(),
          snippet: String.t() | nil,
          suggestion: String.t() | nil,
          docs_url: String.t() | nil
        }

  @impl true
  def message(%__MODULE__{} = e) do
    Caravela.Errors.format(__MODULE__, %{
      message: e.message,
      snippet: e.snippet,
      suggestion: e.suggestion,
      docs_url: e.docs_url
    })
  end
end

defmodule Caravela.Errors do
  @moduledoc """
  Structured compile-time errors for Caravela's DSL and generators.

  Distinct from `Caravela.Error` (which is the runtime *result* struct
  returned from context / generator functions as `{:error, %Caravela.Error{}}`).
  These are **exceptions**: thrown during DSL macro expansion or
  generator execution when a caller's input is malformed.

  Two exception modules cover the surface:

    * `Caravela.DSLError` - raised from inside DSL macros (`entity`,
      `field`, `policy`, `authenticatable`, …) at compile time.
    * `Caravela.GenError` - raised from `Caravela.Gen.*` functions and
      `mix caravela.gen.*` tasks at generator-run time.

  Both carry the same four-part shape: **what went wrong**, **what
  Caravela got** (a code snippet), **a suggested fix**, and a **docs
  URL**. `Exception.message/1` renders the four parts consistently so
  humans, CI, and LLMs all see the same structured output.

  ## Why structured

  Freeform `raise ArgumentError, "bad field"` strings are fine for
  humans reading a terminal but painful for LLM iteration loops - the
  model has to guess what to fix from one line of prose. Structured
  errors let the LLM latch onto the `Suggestion:` block and patch
  correctly on the first try. Same benefit applies to humans opening
  a stack trace from CI without immediate editor context.

  ## Example rendered output

      ** (Caravela.DSLError) `field :title` is missing a type

         Got:
             field :title

         Suggestion:
             field :title, :string, required: true

         See: https://hexdocs.pm/caravela/dsl.html#fields
  """

  @doc false
  @spec format(module(), %{:message => String.t(), optional(atom()) => any()}) :: String.t()
  def format(module, %{message: message} = fields) do
    [
      "** (",
      inspect(module),
      ") ",
      message,
      "\n"
    ]
    |> append_section("Got:", Map.get(fields, :snippet))
    |> append_section("Suggestion:", Map.get(fields, :suggestion))
    |> append_see(Map.get(fields, :docs_url))
    |> IO.iodata_to_binary()
  end

  defp append_section(acc, _label, nil), do: acc
  defp append_section(acc, _label, ""), do: acc

  defp append_section(acc, label, body) do
    [acc, "\n   ", label, "\n", indent_body(body), "\n"]
  end

  defp append_see(acc, nil), do: acc
  defp append_see(acc, url), do: [acc, "\n   See: ", url, "\n"]

  defp indent_body(body) do
    body
    |> String.split("\n")
    |> Enum.map_join("\n", &("       " <> &1))
  end

  @doc """
  Build a `Caravela.DSLError` from a Macro.Env (`__CALLER__`) plus
  message and suggestion. A convenience for macro authors.

      raise Caravela.Errors.dsl(__CALLER__,
              message: "field requires a type",
              suggestion: "field :title, :string")
  """
  @spec dsl(Macro.Env.t() | nil, keyword()) :: Caravela.DSLError.t()
  def dsl(env, fields) when is_list(fields) do
    %Caravela.DSLError{
      message: Keyword.fetch!(fields, :message),
      snippet: Keyword.get(fields, :snippet) || snippet_from_env(env),
      suggestion: Keyword.get(fields, :suggestion),
      docs_url: Keyword.get(fields, :docs_url)
    }
  end

  @doc """
  Build a `Caravela.GenError` for a generator-level failure.
  """
  @spec gen(keyword()) :: Caravela.GenError.t()
  def gen(fields) when is_list(fields) do
    %Caravela.GenError{
      message: Keyword.fetch!(fields, :message),
      snippet: Keyword.get(fields, :snippet),
      suggestion: Keyword.get(fields, :suggestion),
      docs_url: Keyword.get(fields, :docs_url)
    }
  end

  @doc "Extract ~3 lines of source around `env.line` for a snippet."
  @spec snippet_from_env(Macro.Env.t() | nil) :: String.t() | nil
  def snippet_from_env(nil), do: nil

  def snippet_from_env(%Macro.Env{file: file, line: line})
      when is_binary(file) and is_integer(line) do
    case File.read(file) do
      {:ok, contents} ->
        lines = String.split(contents, "\n")
        start = max(line - 1, 1)
        stop = min(line + 1, length(lines))

        body =
          for n <- start..stop do
            marker = if n == line, do: ">>> ", else: "    "
            marker <> Enum.at(lines, n - 1, "")
          end
          |> Enum.join("\n")

        body <> "\n# at " <> Path.relative_to_cwd(file) <> ":" <> Integer.to_string(line)

      {:error, _} ->
        nil
    end
  end

  def snippet_from_env(_), do: nil
end
