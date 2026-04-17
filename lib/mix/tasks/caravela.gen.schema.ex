defmodule Mix.Tasks.Caravela.Gen.Schema do
  @shortdoc "Generate Ecto schemas and a migration from a Caravela domain"

  @moduledoc """
  Generates Ecto schemas and a migration file from a Caravela domain
  declaration.

      mix caravela.gen.schema MyApp.Domains.Library

  Flags:

    * `--dry-run`  — print the generated files without writing anything
    * `--output DIR` — write under `DIR` instead of the project root
    * `--force`    — overwrite existing files without prompting
  """

  use Mix.Task

  alias Caravela.Gen.{EctoSchema, Migration}

  @switches [dry_run: :boolean, output: :string, force: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)

    domain_module =
      case args do
        [mod] -> Module.concat([mod])
        _ -> Mix.raise("Usage: mix caravela.gen.schema <DomainModule>")
      end

    Mix.Task.run("loadpaths")
    Mix.Task.run("compile")

    unless Code.ensure_loaded?(domain_module) do
      Mix.raise("Module #{inspect(domain_module)} is not loaded — is it compiled?")
    end

    unless function_exported?(domain_module, :__caravela_domain__, 0) do
      Mix.raise(
        "#{inspect(domain_module)} does not use Caravela.Domain " <>
          "(no __caravela_domain__/0 was generated)."
      )
    end

    domain = domain_module.__caravela_domain__()

    schemas = EctoSchema.render_all(domain)
    migration = Migration.render(domain)

    files = [migration | schemas]

    root = Keyword.get(opts, :output, File.cwd!())

    if Keyword.get(opts, :dry_run, false) do
      Enum.each(files, fn {path, source} ->
        Mix.shell().info("==> #{path}\n#{source}")
      end)
    else
      Enum.each(files, fn {path, source} ->
        target = Path.join(root, path)
        write_file(target, source, Keyword.get(opts, :force, false))
      end)
    end

    :ok
  end

  defp write_file(path, source, force?) do
    cond do
      File.exists?(path) and not force? ->
        case Mix.shell().yes?("File #{path} exists — overwrite?") do
          true -> do_write(path, source)
          false -> Mix.shell().info("skipped #{path}")
        end

      true ->
        do_write(path, source)
    end
  end

  defp do_write(path, source) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
    Mix.shell().info("* created #{path}")
  end
end
