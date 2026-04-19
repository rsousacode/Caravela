defmodule Caravela.RenderModesGenTest do
  use ExUnit.Case, async: true

  alias Caravela.Gen.{LiveRoute, LiveView, RestController, Svelte}

  defmodule MixedDomain do
    use Caravela.Domain, default_policy: :allow

    entity :authors do
      field :name, :string, required: true
    end

    entity :books, frontend: :rest do
      field :title, :string, required: true
    end
  end

  defmodule AllRestDomain do
    use Caravela.Domain, default_policy: :allow

    entity :books, frontend: :rest do
      field :title, :string, required: true
    end
  end

  defmodule RealtimeDomain do
    use Caravela.Domain, default_policy: :allow

    entity :books, frontend: :rest, realtime: true do
      field :title, :string, required: true
    end
  end

  describe "LiveView.render_all/2" do
    test "skips entities declared with frontend: :rest" do
      domain = MixedDomain.__caravela_domain__()
      files = LiveView.render_all(domain, root: System.tmp_dir!())
      paths = Enum.map(files, fn {path, _source} -> path end)

      # :live entity still produces three LiveViews (index/show/form)
      assert Enum.any?(paths, &String.contains?(&1, "author_live/index.ex"))
      assert Enum.any?(paths, &String.contains?(&1, "author_live/show.ex"))
      assert Enum.any?(paths, &String.contains?(&1, "author_live/form.ex"))

      # :rest entity is skipped entirely by the LiveView generator
      refute Enum.any?(paths, &String.contains?(&1, "book_live/"))
    end

    test "returns no files when every entity is :rest" do
      domain = AllRestDomain.__caravela_domain__()
      assert LiveView.render_all(domain, root: System.tmp_dir!()) == []
    end
  end

  describe "LiveRoute.render/1" do
    test "emits a :live block and a :rest block when the domain mixes modes" do
      domain = MixedDomain.__caravela_domain__()
      snippet = LiveRoute.render(domain)

      assert snippet =~ ~s|live "/authors", AuthorLive.Index, :index|
      assert snippet =~ ~s|caravela_rest "/books", BookController|
      assert snippet =~ "import CaravelaSvelte.Router"
    end

    test "omits the :live block when every entity is :rest" do
      domain = AllRestDomain.__caravela_domain__()
      snippet = LiveRoute.render(domain)

      refute snippet =~ "live \""
      assert snippet =~ ~s|caravela_rest "/books", BookController|
    end

    test "emits realtime: true on the caravela_rest line when the entity opts in" do
      domain = RealtimeDomain.__caravela_domain__()
      snippet = LiveRoute.render(domain)

      assert snippet =~ ~s|caravela_rest "/books", BookController, realtime: true|
    end
  end

  describe "RestController.render_all/2" do
    test "only emits controllers for :rest entities" do
      domain = MixedDomain.__caravela_domain__()
      files = RestController.render_all(domain, root: System.tmp_dir!())
      paths = Enum.map(files, fn {path, _source} -> path end)

      # one controller per :rest entity, none for the :live :authors
      assert Enum.any?(paths, &String.contains?(&1, "book_controller.ex"))
      refute Enum.any?(paths, &String.contains?(&1, "author_controller.ex"))
    end

    test "emits a controller wiring put_field_access + structured errors" do
      domain = AllRestDomain.__caravela_domain__()
      [{_path, source}] = RestController.render_all(domain, root: System.tmp_dir!())

      assert source =~ "CaravelaSvelte.Caravela"
      assert source =~ "put_field_access"
      assert source =~ "ChangesetTranslator.translate(changeset)"
      assert source =~ "CaravelaSvelte.render"
    end

    test "emits broadcast_patch call sites when realtime: true" do
      domain = RealtimeDomain.__caravela_domain__()
      [{_path, source}] = RestController.render_all(domain, root: System.tmp_dir!())

      assert source =~ "broadcast(entity, context, :create)"
      assert source =~ "broadcast(updated, context, :update)"
      assert source =~ "broadcast(entity, context, :delete)"
      assert source =~ "CS.broadcast_patch("
    end

    test "omits broadcast hooks when realtime is off" do
      domain = AllRestDomain.__caravela_domain__()
      [{_path, source}] = RestController.render_all(domain, root: System.tmp_dir!())

      refute source =~ "broadcast_patch"
      refute source =~ "patch_ops"
    end

    # Regression — 0.13.2 — a stray `end` after `<%= @custom_marker %>` in
    # `priv/templates/rest_controller.eex` shipped a controller that failed
    # to compile with `unexpected reserved word: end`. Every other test in
    # this file only regex-matched the emitted source; none parsed it, so
    # the bug landed unblocked. Keep this test whenever adding a new
    # generator: if the output isn't valid Elixir, nothing downstream
    # matters.
    test "emits valid Elixir for every :rest entity / realtime combination" do
      for {domain_module, label} <- [
            {MixedDomain, "mixed"},
            {AllRestDomain, "all_rest"},
            {RealtimeDomain, "realtime"}
          ] do
        domain = domain_module.__caravela_domain__()

        for {_path, source} <- RestController.render_all(domain, root: System.tmp_dir!()) do
          assert {:ok, _} = Code.string_to_quoted(source),
                 "#{label} domain emitted invalid Elixir:\n#{source}"
        end
      end
    end
  end

  describe "Svelte @caravela-* metadata header" do
    test "stamps entity name and frontend mode on :live components" do
      domain = MixedDomain.__caravela_domain__()
      {_path, source} = Svelte.render_component(domain, entity(domain, :authors), :index)

      assert source =~ "@caravela-entity Author"
      assert source =~ "@caravela-mode live"
      refute source =~ "@caravela-realtime"
    end

    test "stamps frontend: rest when the entity is :rest" do
      domain = MixedDomain.__caravela_domain__()
      {_path, source} = Svelte.render_component(domain, entity(domain, :books), :index)

      assert source =~ "@caravela-entity Book"
      assert source =~ "@caravela-mode rest"
    end

    test "includes @caravela-realtime true when the entity opts in" do
      domain = RealtimeDomain.__caravela_domain__()
      {_path, source} = Svelte.render_component(domain, entity(domain, :books), :index)

      assert source =~ "@caravela-realtime true"
    end
  end

  defp entity(domain, name), do: Enum.find(domain.entities, &(&1.name == name))
end
