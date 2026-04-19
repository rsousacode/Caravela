defmodule Mix.Tasks.Caravela.Ir do
  @shortdoc "Print a Caravela domain's IR as JSON"

  @moduledoc """
  Print the public Intermediate Representation of a Caravela domain
  as JSON. Intended for consumption by editors, LLMs, and external
  tooling that wants a structured view of the domain without parsing
  Elixir source.

      mix caravela.ir MyApp.Domains.Library

  Flags:

    * `--output PATH` — write to a file instead of stdout
    * `--no-pretty` — emit compact JSON (one line, no indentation)

  The emitted shape is documented in `Caravela.IR`. Anonymous
  functions inside policies are not included — only their metadata
  (the fact that a rule exists, its arity, its target entity).
  """

  use Mix.Task

  alias Caravela.{IR, MixHelpers}

  @switches [output: :string, pretty: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)
    domain = MixHelpers.load_domain!(args)

    json = IR.to_json(IR.of(domain), pretty: Keyword.get(opts, :pretty, true))

    case Keyword.get(opts, :output) do
      nil ->
        Mix.shell().info(json)

      path ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, json)
        Mix.shell().info("wrote #{path}")
    end

    :ok
  end
end
