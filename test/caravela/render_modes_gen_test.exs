defmodule Caravela.RenderModesGenTest do
  use ExUnit.Case, async: true

  alias Caravela.Gen.{LiveRoute, LiveView}

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
  end
end
