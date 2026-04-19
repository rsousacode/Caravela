# Not async: the "config :caravela, :changeset_translator" test
# mutates Application env, which other async tests would see.
defmodule Caravela.ChangesetTranslatorTest do
  use ExUnit.Case, async: false

  alias Caravela.ChangesetTranslator

  # Minimal schema used only to build changesets with known error
  # shapes — we never insert, so no repo / migration is needed.
  defmodule Book do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :title, :string
      field :pages, :integer
      field :isbn, :string
    end

    def changeset(attrs) do
      %__MODULE__{}
      |> cast(attrs, [:title, :pages, :isbn])
      |> validate_required([:title])
      |> validate_length(:title, min: 3, max: 120)
      |> validate_number(:pages, greater_than: 0, less_than: 10_000)
      |> validate_format(:isbn, ~r/^\d{13}$/)
    end
  end

  # Faux Gettext backend exposing the exact Gettext.Backend callbacks
  # the translator calls. Records its invocations so tests can assert
  # on exactly what got delegated.
  defmodule FakeGettext do
    def start_link do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def calls do
      if Process.whereis(__MODULE__) do
        Agent.get(__MODULE__, & &1)
      else
        []
      end
    end

    def dgettext(domain, msg, bindings) do
      record({:dgettext, domain, msg, bindings})
      "TR:" <> msg
    end

    def dngettext(domain, singular, plural, count, bindings) do
      record({:dngettext, domain, singular, plural, count, bindings})
      "TRP:#{singular}/#{plural}/#{count}"
    end

    defp record(call) do
      if Process.whereis(__MODULE__) do
        Agent.update(__MODULE__, &[call | &1])
      end
    end
  end

  describe "translate/2 — structured shape" do
    test "returns %{field => [%{code, params, message}]} for required fields" do
      errors = ChangesetTranslator.translate(Book.changeset(%{}))

      assert [%{code: :required, params: _, message: message}] = errors.title
      assert is_binary(message)
      assert message =~ "blank"
    end

    test "carries sub-kind in :params rather than mangling the code" do
      errors = ChangesetTranslator.translate(Book.changeset(%{title: "ab"}))

      [%{code: code, params: params}] = errors.title
      assert code == :length
      assert params[:kind] == :min
      assert params[:count] == 3
    end

    test "interpolates %{param} placeholders into :message" do
      errors = ChangesetTranslator.translate(Book.changeset(%{title: "ab"}))
      [%{message: message}] = errors.title
      assert message =~ "3"
    end

    test "strips :validation and :constraint from :params (they become :code)" do
      errors = ChangesetTranslator.translate(Book.changeset(%{}))
      [%{params: params}] = errors.title

      refute Map.has_key?(params, :validation)
      refute Map.has_key?(params, :constraint)
    end

    test "defaults to :invalid code when neither :validation nor :constraint is present" do
      result = ChangesetTranslator.translate_error({"something broke", []}, nil)
      assert result.code == :invalid
      assert result.params == %{}
      assert result.message == "something broke"
    end
  end

  describe "translate/2 — translator plumbing" do
    setup do
      {:ok, _pid} = FakeGettext.start_link()
      :ok
    end

    test "routes simple errors through dgettext on the configured translator" do
      errors =
        ChangesetTranslator.translate(Book.changeset(%{}), translator: FakeGettext)

      [%{message: message}] = errors.title
      assert String.starts_with?(message, "TR:")

      assert Enum.any?(FakeGettext.calls(), fn
               {:dgettext, "errors", _msg, _bindings} -> true
               _ -> false
             end)
    end

    test "routes :count errors through dngettext" do
      errors =
        ChangesetTranslator.translate(Book.changeset(%{title: "ab"}),
          translator: FakeGettext
        )

      [%{message: message}] = errors.title
      assert String.starts_with?(message, "TRP:")

      assert Enum.any?(FakeGettext.calls(), fn
               {:dngettext, "errors", _s, _p, 3, _bindings} -> true
               _ -> false
             end)
    end

    test "translator: false forces pass-through interpolation" do
      errors =
        ChangesetTranslator.translate(Book.changeset(%{title: "ab"}), translator: false)

      [%{message: message}] = errors.title
      refute String.starts_with?(message, "TR")
      assert message =~ "3"
    end

    test "falls back to interpolation when translator module is missing callbacks" do
      defmodule NotATranslator do
        # intentionally no dgettext/3 or dngettext/5
      end

      errors =
        ChangesetTranslator.translate(Book.changeset(%{}), translator: NotATranslator)

      [%{message: message}] = errors.title
      assert is_binary(message)
      refute message == ""
    end

    test "config :caravela, :changeset_translator is honoured when no opt is passed" do
      Application.put_env(:caravela, :changeset_translator, FakeGettext)

      on_exit(fn -> Application.delete_env(:caravela, :changeset_translator) end)

      errors = ChangesetTranslator.translate(Book.changeset(%{}))
      [%{message: message}] = errors.title

      assert String.starts_with?(message, "TR:")
    end
  end

  describe "translate_error/2 — single error entry" do
    test "accepts either a translator module or the keyword-list form" do
      raw = {"is invalid", [validation: :format]}

      kw_result = ChangesetTranslator.translate_error(raw, translator: nil)
      mod_result = ChangesetTranslator.translate_error(raw, nil)

      assert kw_result == mod_result
      assert kw_result.code == :format
    end
  end
end
