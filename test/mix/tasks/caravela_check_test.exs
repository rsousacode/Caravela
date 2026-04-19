defmodule Mix.Tasks.Caravela.CheckTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration tests for `mix caravela.check`.

  We exercise the task via `System.cmd/3` so the BEAM-file discovery
  actually runs in a fresh Mix task context. Running it in-process
  wouldn't go through `Mix.Task.run/2` the way a user invocation
  does.
  """

  @tag :slow
  test "exits 0 with a green summary when every fixture domain checks out" do
    {out, exit_code} =
      System.cmd("mix", ["caravela.check", "--quiet"],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert exit_code == 0, "caravela.check failed:\n#{out}"
    assert out =~ "caravela.check"
    assert out =~ "step(s) passed"
  end

  @tag :slow
  test "--only narrows to a single domain" do
    {out, exit_code} =
      System.cmd(
        "mix",
        ["caravela.check", "--only", "MyApp.Domains.Library", "--quiet"],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert exit_code == 0, out
    assert out =~ "step(s) passed"
  end

  @tag :slow
  test "--only errors cleanly on a non-domain module" do
    {out, exit_code} =
      System.cmd(
        "mix",
        ["caravela.check", "--only", "NotADomainModule"],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert exit_code != 0
    assert out =~ "is not a Caravela domain"
  end
end
