defmodule Caravela do
  @moduledoc """
  Caravela — a schema-driven, composable full-stack framework for Phoenix.

  **Declare your domain. Sail with the generated code.**

  Start with `use Caravela.Domain` in a module under `lib/<app>/domains/`
  to declare entities, fields, and relations. Then run
  `mix caravela.gen.schema <Module>` to generate Ecto schemas and a
  migration. See `Caravela.Domain` for the DSL reference.
  """

  @doc "Returns the compiled IR of a Caravela domain module."
  def domain!(module) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :__caravela_domain__, 0) do
      raise ArgumentError, "#{inspect(module)} is not a Caravela.Domain"
    end

    module.__caravela_domain__()
  end
end
