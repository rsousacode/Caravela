defmodule Caravela.MixHelpers do
  @moduledoc false

  @doc """
  Resolve a domain module from mix task args and ensure it is loaded
  and uses `Caravela.Domain`.
  """
  def load_domain!([mod_string | _]) do
    domain_module = Module.concat([mod_string])

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

    domain_module.__caravela_domain__()
  end

  def load_domain!(_),
    do: Mix.raise("Usage: mix caravela.gen.<task> <DomainModule>")

  @doc """
  Write each `{path, source}` file under `root`, prompting before
  overwrite unless `force?`.
  """
  def write_files(files, root, force?, dry_run?) do
    if dry_run? do
      Enum.each(files, fn {path, source} ->
        Mix.shell().info("==> #{path}\n#{source}")
      end)
    else
      Enum.each(files, fn {path, source} ->
        target = Path.join(root, path)
        write_file(target, source, force?)
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
