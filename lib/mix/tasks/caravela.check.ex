defmodule Mix.Tasks.Caravela.Check do
  @shortdoc "Validate every Caravela domain: compile, generate dry-run, optional tests/dialyzer"

  @moduledoc """
  One-stop validation for a Caravela-using project.

  Runs, in order:

    1. `mix compile` - everything must compile.
    2. Discover every module that uses `Caravela.Domain`.
    3. For each domain, render every applicable generator in memory
       (no files written) and confirm it doesn't raise.
    4. Optionally run `mix test` (`--tests`) and/or `mix dialyzer`
       (`--dialyzer`).

  Exits 0 on green, non-zero with a per-domain / per-generator
  summary otherwise. Intended as the **single oracle** for LLM
  iteration loops and CI - one command, one signal.

  ## Flags

    * `--tests` - also run `mix test`.
    * `--dialyzer` - also run `mix dialyzer` (requires `:dialyxir`).
    * `--only DOMAIN` - check a single domain module instead of all.
    * `--quiet` - suppress per-step output, print final summary only.
  """

  use Mix.Task

  alias Caravela.IR

  @switches [tests: :boolean, dialyzer: :boolean, only: :string, quiet: :boolean]

  @core_generators [
    {:schema, Caravela.Gen.EctoSchema, :render_all, :with_opts},
    {:migration, Caravela.Gen.Migration, :render, :with_opts},
    {:context, Caravela.Gen.Context, :render, :with_opts},
    {:controllers, Caravela.Gen.Controller, :render_all, :with_opts},
    {:live_views, Caravela.Gen.LiveView, :render_all, :with_opts},
    {:svelte, Caravela.Gen.Svelte, :render_all, :with_opts},
    {:router_scope, Caravela.Gen.RouterScope, :render, :domain_only}
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _args, _} = OptionParser.parse(argv, switches: @switches)
    quiet? = Keyword.get(opts, :quiet, false)

    # 1. Compile (required before discovery).
    Mix.Task.run("compile")

    # 2. Discover domains.
    domains = discover_domains(Keyword.get(opts, :only))

    if domains == [] do
      Mix.raise("No Caravela domains found. Are any modules using `use Caravela.Domain`?")
    end

    log(quiet?, "\nChecking #{length(domains)} domain(s):")

    # 3. Per-domain checks.
    results =
      Enum.map(domains, fn mod ->
        result = check_domain(mod, quiet?)
        {mod, result}
      end)

    # 4. Optional tests / dialyzer.
    extra =
      []
      |> maybe_tests(Keyword.get(opts, :tests, false), quiet?)
      |> maybe_dialyzer(Keyword.get(opts, :dialyzer, false), quiet?)

    # 5. Summarize.
    summary(results, extra, quiet?)
  end

  # --- Discovery --------------------------------------------------------

  defp discover_domains(nil) do
    # Scan every .beam file under the current project's compile path.
    # `:code.all_loaded/0` only covers modules already in memory, which
    # misses domains that compiled but haven't been touched yet. Cold-
    # starting from .beam files is what `mix xref` and similar do.
    compile_paths()
    |> Enum.flat_map(&list_beams/1)
    |> Enum.map(&beam_to_module/1)
    |> Enum.filter(&caravela_domain?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp discover_domains(only) do
    mod = Module.concat([only])
    unless caravela_domain?(mod), do: Mix.raise("#{inspect(mod)} is not a Caravela domain.")
    [mod]
  end

  defp caravela_domain?(mod) when is_atom(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :__caravela_domain__, 0)
  end

  defp compile_paths do
    # Include the current project's compile path plus every loaded
    # app's code path. Consumer apps using Caravela as a dep will have
    # their own compile path; tests exercise test/support via the test
    # env's compile path.
    project_path = Mix.Project.compile_path()

    consumer_paths =
      case :code.get_path() do
        paths when is_list(paths) ->
          Enum.map(paths, &to_string/1)

        _ ->
          []
      end

    [project_path | consumer_paths] |> Enum.uniq()
  end

  defp list_beams(dir) do
    case File.ls(dir) do
      {:ok, files} -> for f <- files, String.ends_with?(f, ".beam"), do: Path.join(dir, f)
      {:error, _} -> []
    end
  end

  defp beam_to_module(path) do
    path
    |> Path.basename(".beam")
    |> String.to_atom()
  end

  # --- Per-domain checks -----------------------------------------------

  defp check_domain(mod, quiet?) do
    log(quiet?, "\n  #{inspect(mod)}")

    steps = [
      {"IR", fn -> IR.of(mod) end} | generator_steps(mod)
    ]

    Enum.map(steps, fn {name, thunk} ->
      case run_step(thunk) do
        :ok ->
          log(quiet?, "    \e[32m✓\e[0m #{name}")
          {name, :ok}

        {:error, reason} ->
          log(quiet?, "    \e[31m✗\e[0m #{name}: #{format_reason(reason)}")
          {name, {:error, reason}}
      end
    end)
  end

  defp generator_steps(mod) do
    domain = mod.__caravela_domain__()

    core =
      for {label, gen_mod, fun, shape} <- @core_generators,
          do: gen_step(label, gen_mod, fun, domain, shape)

    auth =
      if Caravela.Schema.Domain.authenticated?(domain) do
        [gen_step(:auth, Caravela.Gen.Auth, :render_all, domain, :with_opts, skip_ui: true)]
      else
        []
      end

    graphql =
      if Code.ensure_loaded?(Absinthe.Schema.Notation) do
        [gen_step(:graphql, Caravela.Gen.GraphQL, :render_all, domain, :with_opts)]
      else
        []
      end

    core ++ auth ++ graphql
  end

  defp gen_step(label, mod, fun, domain, shape, extra_opts \\ []) do
    args =
      case shape do
        :with_opts -> [domain, extra_opts]
        :domain_only -> [domain]
      end

    {to_string(label),
     fn ->
       # Generators write nothing - they're pure functions returning
       # {path, source} tuples. Just call and let any raise surface.
       apply(mod, fun, args)
     end}
  end

  defp run_step(thunk) do
    try do
      _ = thunk.()
      :ok
    rescue
      e -> {:error, e}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  # --- Optional steps --------------------------------------------------

  defp maybe_tests(acc, false, _), do: acc

  defp maybe_tests(acc, true, quiet?) do
    log(quiet?, "\nRunning tests…")

    case System.cmd("mix", ["test", "--color"], into: IO.stream(:stdio, :line)) do
      {_, 0} -> [{"tests", :ok} | acc]
      {_, code} -> [{"tests", {:error, "mix test exited #{code}"}} | acc]
    end
  end

  defp maybe_dialyzer(acc, false, _), do: acc

  defp maybe_dialyzer(acc, true, quiet?) do
    log(quiet?, "\nRunning Dialyzer…")

    case System.cmd("mix", ["dialyzer"], into: IO.stream(:stdio, :line)) do
      {_, 0} -> [{"dialyzer", :ok} | acc]
      {_, code} -> [{"dialyzer", {:error, "mix dialyzer exited #{code}"}} | acc]
    end
  end

  # --- Summary ---------------------------------------------------------

  defp summary(domain_results, extra, quiet?) do
    flat =
      Enum.flat_map(domain_results, fn {mod, steps} ->
        Enum.map(steps, fn {name, r} -> {"#{inspect(mod)} / #{name}", r} end)
      end) ++ extra

    failures = Enum.filter(flat, fn {_, r} -> r != :ok end)
    total = length(flat)
    failed = length(failures)

    if failures == [] do
      unless quiet?, do: Mix.shell().info("")
      Mix.shell().info("\e[32m✓ caravela.check - #{total} step(s) passed.\e[0m")
      :ok
    else
      Mix.shell().info("\n\e[31m✗ caravela.check - #{failed}/#{total} step(s) failed:\e[0m")

      Enum.each(failures, fn {name, {:error, reason}} ->
        Mix.shell().info("  • #{name}: #{format_reason(reason)}")
      end)

      exit({:shutdown, 1})
    end
  end

  # --- Helpers ---------------------------------------------------------

  defp log(true, _msg), do: :ok
  defp log(false, msg), do: Mix.shell().info(msg)

  defp format_reason(%{__struct__: _} = exception) when is_exception(exception),
    do: Exception.message(exception)

  defp format_reason({kind, reason}),
    do: "caught #{kind}: #{inspect(reason)}"

  defp format_reason(other), do: inspect(other)
end
