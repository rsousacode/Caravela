defmodule Caravela.RouterTest do
  use ExUnit.Case, async: true

  alias Caravela.Router
  alias Caravela.Schema.{Domain, Entity}

  # Expand-only tests: we exercise the AST `caravela_routes/1` would
  # emit without standing up a Phoenix.Router in-process. That keeps
  # the test fast and avoids Phoenix-version drift.
  defp expand(%Domain{} = domain, opts \\ []) do
    domain
    |> Router.expand_routes(opts)
    |> Macro.to_string()
  end

  defmodule MixedDomain do
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

  describe "expand_routes/2 — :live entities" do
    test "emits a `live` route per CRUD action for every :live entity" do
      src = expand(MixedDomain.__caravela_domain__())

      assert src =~ ~s|live("/authors", AuthorLive.Index, :index)|
      assert src =~ ~s|live("/authors/new", AuthorLive.Form, :new)|
      assert src =~ ~s|live("/authors/:id", AuthorLive.Show, :show)|
      assert src =~ ~s|live("/authors/:id/edit", AuthorLive.Form, :edit)|
    end

    test "skips entities whose frontend is :rest" do
      src = expand(MixedDomain.__caravela_domain__())

      refute src =~ "BookLive"
      refute src =~ "ChapterLive"
    end

    test "wraps :live routes in a live_session when :session opts are provided" do
      src =
        expand(MixedDomain.__caravela_domain__(),
          session: [on_mount: {MyAppWeb.Auth, :require_user}]
        )

      assert src =~ "live_session("
      assert src =~ "caravela_live_authors"
      assert src =~ "on_mount:"
    end
  end

  describe "expand_routes/2 — :rest entities" do
    test "emits a `caravela_rest` route per :rest entity" do
      src = expand(MixedDomain.__caravela_domain__())

      assert src =~ ~s|caravela_rest("/books", BookController)|
    end

    test "appends realtime: true when the entity opts in" do
      src = expand(MixedDomain.__caravela_domain__())

      assert src =~ ~s|caravela_rest("/chapters", ChapterController, realtime: true)|
    end

    test "skips entities whose frontend is :live" do
      src = expand(MixedDomain.__caravela_domain__())

      refute src =~ "AuthorController"
    end
  end

  describe "versioned domains" do
    defmodule VersionedDomain do
      use Caravela.Domain, default_policy: :allow

      version "v1"

      entity :books do
        field :title, :string, required: true
      end

      entity :chapters, frontend: :rest do
        field :number, :integer
      end
    end

    test "inserts the version segment into :live module aliases" do
      src = expand(VersionedDomain.__caravela_domain__())

      assert src =~ "V1.BookLive.Index"
      assert src =~ "V1.BookLive.Show"
      assert src =~ "V1.BookLive.Form"
    end

    test "inserts the version segment into :rest controller aliases" do
      src = expand(VersionedDomain.__caravela_domain__())

      assert src =~ "V1.ChapterController"
    end
  end

  describe "edge cases" do
    test "domains with no entities still expand to valid AST" do
      empty = %Domain{module: MyApp.Empty, entities: []}

      # Should not raise.
      ast = Router.expand_routes(empty, [])
      assert is_tuple(ast)
    end

    test ":live-only domains omit the :rest block (no caravela_rest calls)" do
      src =
        expand(%Domain{
          module: MyApp.Only,
          entities: [%Entity{name: :books, frontend: :live}]
        })

      refute src =~ "caravela_rest"
    end

    test ":rest-only domains omit the :live block (no live calls)" do
      src =
        expand(%Domain{
          module: MyApp.Only,
          entities: [%Entity{name: :books, frontend: :rest}]
        })

      refute src =~ ~s|live(|
    end
  end
end
