defmodule Caravela.Gen.UpstreamTagRegressionTest do
  @moduledoc """
  Catches stale `<LiveSvelte.svelte>` references in any generator
  output. v0.11 committed to the `caravela_svelte` convergence but
  the `--with-domain` form template was missed in that pass
  (bug_improvements_3.md §1.1), and v0.13 was still emitting the
  old tag in six auth LiveView templates (§1.3).

  This test runs every generator that emits Phoenix/EEx/Svelte
  output against a representative domain and asserts `LiveSvelte`
  never appears in the rendered source — a single checkpoint that
  stops any future template regression dead.
  """

  use ExUnit.Case, async: true

  alias Caravela.Gen.{LiveView, RestController, Svelte}

  defmodule DomainFixture do
    use Caravela.Domain, default_policy: :allow

    entity :authors do
      field :name, :string, required: true
    end

    entity :books, frontend: :rest do
      field :title, :string, required: true
    end

    entity :chapters, frontend: :rest, realtime: true do
      field :number, :integer
    end
  end

  defp assert_no_live_svelte({path, source}) do
    refute source =~ "LiveSvelte.svelte",
           """
           `#{path}` still contains `LiveSvelte.svelte` — v0.11 moved generated
           output to `<CaravelaSvelte.svelte>`. If you're adding a new template,
           mount Svelte components via `<CaravelaSvelte.svelte>` instead.
           """
  end

  describe "Caravela.Gen.LiveView" do
    test "no :live LiveView emits `<LiveSvelte.svelte>`" do
      domain = DomainFixture.__caravela_domain__()

      domain
      |> LiveView.render_all(root: System.tmp_dir!())
      |> Enum.each(&assert_no_live_svelte/1)
    end

    test "--with-domain variant also produces `<CaravelaSvelte.svelte>`" do
      domain = DomainFixture.__caravela_domain__()

      domain
      |> LiveView.render_all(root: System.tmp_dir!(), with_domain: true)
      |> Enum.filter(fn {path, _} -> String.ends_with?(path, "form.ex") end)
      |> Enum.each(fn {_path, src} ->
        # Positive check — the tag is present.
        assert src =~ "<CaravelaSvelte.svelte"
      end)

      domain
      |> LiveView.render_all(root: System.tmp_dir!(), with_domain: true)
      |> Enum.each(&assert_no_live_svelte/1)
    end
  end

  describe "Caravela.Gen.RestController" do
    test "no :rest controller mentions the old tag" do
      domain = DomainFixture.__caravela_domain__()

      domain
      |> RestController.render_all(root: System.tmp_dir!())
      |> Enum.each(&assert_no_live_svelte/1)
    end
  end

  describe "Caravela.Gen.Svelte" do
    test "no generated component or TS file carries `LiveSvelte` in comments" do
      domain = DomainFixture.__caravela_domain__()

      domain
      |> Svelte.render_all(root: System.tmp_dir!())
      |> Enum.each(fn {path, source} ->
        # We don't forbid "live" (the prop name) or "LiveHandle" (the
        # type alias we own), but `LiveSvelte` specifically points at
        # the unforked upstream and shouldn't appear anywhere.
        refute source =~ "LiveSvelte",
               "`#{path}` references `LiveSvelte`; expected `caravela_svelte` only."
      end)
    end
  end
end
