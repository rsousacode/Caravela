defmodule Caravela.MCP.Tool.ValidateDsl do
  @moduledoc """
  MCP tool: compile a candidate Caravela domain DSL and report any
  errors as structured data.

  The tool spawns a fresh VM process with a short-lived code path so
  the candidate module doesn't pollute the caller's runtime. Success
  returns the compiled module's IR (so the caller can verify the
  shape); failure returns the `DSLError` / `GenError` / `CompileError`
  payload Caravela raises.

  ## Security note

  The candidate source is `Code.eval_string/1`-compiled. That's
  arbitrary Elixir execution. The server intentionally scopes this
  tool to localhost stdio transport in 0.10 — when HTTP transport
  lands, this tool MUST be gated behind auth + sandboxed further
  (see the future-work section in `caravela_plan/phoenix/llm_friendliness.md`).
  """

  @behaviour Caravela.MCP.Tool

  alias Caravela.IR
  alias Caravela.MCP.Tool

  @impl true
  @spec name() :: String.t()
  def name, do: "caravela__validate_dsl"

  @impl true
  @spec description() :: String.t()
  def description do
    "Compile a candidate Caravela domain DSL source and report " <>
      "errors (DSLError / CompileError) as structured data. On success, " <>
      "returns the compiled module's IR."
  end

  @impl true
  @spec input_schema() :: map()
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "source" => %{
          "type" => "string",
          "description" =>
            "Complete Elixir source for a module that uses " <>
              "`Caravela.Domain`. Must define a module; the tool compiles it " <>
              "and returns the IR if successful."
        }
      },
      "required" => ["source"]
    }
  end

  @impl true
  @spec call(map()) :: {:ok, [map()]} | {:error, String.t()}
  def call(%{"source" => source}) when is_binary(source) do
    try do
      [{module, _binary}] = Code.compile_string(source)

      if function_exported?(module, :__caravela_domain__, 0) do
        ir = IR.of(module)
        {:ok, Tool.text_content(%{ok: true, module: inspect(module), ir: ir})}
      else
        {:ok,
         Tool.text_content(%{
           ok: false,
           error: %{
             kind: "not_a_domain",
             message:
               "#{inspect(module)} compiled but does not `use Caravela.Domain`"
           }
         })}
      end
    rescue
      e in [Caravela.DSLError, Caravela.GenError] ->
        {:ok, Tool.text_content(%{ok: false, error: format_caravela_error(e)})}

      e in CompileError ->
        {:ok,
         Tool.text_content(%{
           ok: false,
           error: %{kind: "compile_error", message: Exception.message(e)}
         })}

      e ->
        {:ok,
         Tool.text_content(%{
           ok: false,
           error: %{
             kind: "exception",
             class: inspect(e.__struct__),
             message: Exception.message(e)
           }
         })}
    end
  end

  def call(_), do: {:error, "missing required argument `source`"}

  defp format_caravela_error(%{__struct__: mod} = err) do
    %{
      kind: kind_for(mod),
      message: err.message,
      snippet: err.snippet,
      suggestion: err.suggestion,
      docs_url: err.docs_url
    }
  end

  defp kind_for(Caravela.DSLError), do: "dsl_error"
  defp kind_for(Caravela.GenError), do: "gen_error"
  defp kind_for(_), do: "unknown"
end
