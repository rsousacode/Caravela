defmodule Caravela.ContextIntegrationTest do
  @moduledoc """
  Compiles the generated context source into a unique namespace with a
  stub Repo and exercises the CRUD functions. Proves that the template
  wires authorization and hooks correctly end-to-end.
  """

  use ExUnit.Case, async: false

  alias Caravela.Gen.{Context, EctoSchema}

  setup do
    domain = MyApp.Domains.Library.__caravela_domain__()
    suffix = "IT#{System.unique_integer([:positive])}"
    stub_repo = Module.concat(["MyApp", suffix, "Repo"])

    # A tiny in-memory stub that records calls and can be seeded with
    # return values. All generated schemas and the context module get
    # rewritten into the `suffix` namespace so nothing clashes with
    # other tests or repeat runs.
    defmodule_stub_repo(stub_repo)

    # Compile each generated schema into the new namespace.
    for {_path, src} <- EctoSchema.render_all(domain) do
      src
      |> String.replace("MyApp.Library", "MyApp.#{suffix}.Library")
      |> String.replace("MyApp.Domains.Library", "MyApp.Domains.Library")
      |> Code.compile_string()
    end

    # Compile the context with MyApp.Repo rewritten to the stub.
    {_path, ctx_src} = Context.render(domain)

    ctx_src
    |> String.replace("MyApp.Library", "MyApp.#{suffix}.Library")
    |> String.replace("alias MyApp.Repo", "alias #{inspect(stub_repo)}")
    |> String.replace(~r/\bRepo\./, "Repo.")
    |> Code.compile_string()

    on_exit(fn -> StubRepoServer.reset(stub_repo) end)

    {:ok,
     context_mod: Module.concat(["MyApp", suffix, "Library"]),
     book_mod: Module.concat(["MyApp", suffix, "Library", "Book"]),
     repo: stub_repo}
  end

  defp defmodule_stub_repo(mod) do
    :ok = StubRepoServer.ensure_started()

    Code.compile_quoted(
      quote do
        defmodule unquote(mod) do
          @mod unquote(mod)
          def all(query), do: StubRepoServer.record_and_return(@mod, {:all, query}, [])
          def get(query, id), do: StubRepoServer.record_and_return(@mod, {:get, query, id}, nil)

          def get!(query, id),
            do: StubRepoServer.record_and_return(@mod, {:get!, query, id}, nil)

          def insert(changeset),
            do: StubRepoServer.record_and_return(@mod, {:insert, changeset}, {:ok, :inserted})

          def update(changeset),
            do: StubRepoServer.record_and_return(@mod, {:update, changeset}, {:ok, :updated})

          def delete(struct),
            do: StubRepoServer.record_and_return(@mod, {:delete, struct}, {:ok, :deleted})
        end
      end
    )
  end

  describe "read path" do
    test "list_books runs apply_read_permission and Repo.all", %{
      context_mod: ctx,
      repo: repo
    } do
      ctx.list_books(%{current_user: %{role: :admin}})
      assert {:all, _q} = StubRepoServer.last_call(repo)
    end
  end

  describe "create path" do
    test "blocks when can_create denies", %{context_mod: ctx, book_mod: book, repo: repo} do
      StubRepoServer.reset(repo)

      assert {:error, :unauthorized} =
               ctx.create_book(%{"title" => "x"}, %{current_user: %{role: :viewer}})

      assert StubRepoServer.calls(repo) == []
      _ = book
    end

    test "inserts when can_create allows", %{context_mod: ctx, repo: repo} do
      StubRepoServer.reset(repo)

      assert {:ok, :inserted} =
               ctx.create_book(%{"title" => "abc"}, %{current_user: %{role: :editor}})

      assert {:insert, %Ecto.Changeset{}} = StubRepoServer.last_call(repo)
    end
  end

  describe "update path" do
    test "blocks when can_update denies", %{context_mod: ctx, book_mod: book, repo: repo} do
      StubRepoServer.reset(repo)
      b = struct!(book, %{id: "b1", title: "a"})

      assert {:error, :unauthorized} =
               ctx.update_book(b, %{"title" => "z"}, %{current_user: %{role: :editor}})

      assert StubRepoServer.calls(repo) == []
    end

    test "updates when can_update allows", %{context_mod: ctx, book_mod: book, repo: repo} do
      StubRepoServer.reset(repo)
      b = struct!(book, %{id: "b1", title: "a"})

      assert {:ok, :updated} =
               ctx.update_book(b, %{"title" => "zed"}, %{current_user: %{role: :admin}})

      assert {:update, %Ecto.Changeset{}} = StubRepoServer.last_call(repo)
    end
  end

  describe "delete path" do
    test "runs on_delete hook and surfaces its error", %{context_mod: ctx, repo: repo} do
      # :authors has on_delete returning {:error, :has_published_books}
      # when the context carries has_published_books: true. But
      # can_delete fallback returns :ok (no rule declared for authors).
      StubRepoServer.reset(repo)
      author_mod = ctx |> Module.split() |> Enum.drop(-1) |> Kernel.++(["Library", "Author"])
      author_mod = Module.concat(author_mod)
      a = struct!(author_mod, %{id: "a1", name: "x"})

      assert {:error, :has_published_books} =
               ctx.delete_author(a, %{has_published_books: true})

      assert StubRepoServer.calls(repo) == []
    end

    test "proceeds to Repo.delete when hooks return :ok", %{context_mod: ctx, repo: repo} do
      StubRepoServer.reset(repo)
      book_mod = Module.concat([ctx, "Book"])
      b = struct!(book_mod, %{id: "b1", title: "a"})
      assert {:ok, :deleted} = ctx.delete_book(b, %{current_user: %{role: :admin}})
      assert {:delete, _} = StubRepoServer.last_call(repo)
    end

    test "blocks when can_delete denies", %{context_mod: ctx, repo: repo} do
      StubRepoServer.reset(repo)
      book_mod = Module.concat([ctx, "Book"])
      b = struct!(book_mod, %{id: "b1", title: "a"})
      assert {:error, :unauthorized} = ctx.delete_book(b, %{current_user: %{role: :editor}})
      assert StubRepoServer.calls(repo) == []
    end
  end
end
