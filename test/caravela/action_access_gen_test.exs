defmodule Caravela.ActionAccessGenTest do
  use ExUnit.Case, async: true

  alias Caravela.Gen.{Context, LiveView, RestController, Svelte}

  # Policies chosen to exercise every action-access path:
  #   * :authors - no policy block; falls through to the deny-all
  #     fallback (default_policy: :deny below).
  #   * :books - arity-1 gates on `:create` and `:delete`; no
  #     `:update` gate. Expected: arity-3 expression for :create and
  #     :delete, and a fallback arity-3 for :update.
  #   * :journals - arity-2 gate on `:update`; should compile to the
  #     literal `:per_record` in `compute_action_access/2` and get
  #     resolved by `action_access/3`.
  defmodule FixtureDomain do
    use Caravela.Domain, default_policy: :deny

    entity :authors do
      field :name, :string, required: true
    end

    entity :books do
      field :title, :string, required: true
    end

    entity :journals, frontend: :rest do
      field :name, :string, required: true
    end

    policy :books do
      allow :create, fn actor -> actor.role == :admin end
      allow :delete, fn actor -> actor.role == :admin end
    end

    policy :journals do
      allow :update, fn _actor, record -> record.archived == false end
    end
  end

  setup do
    {:ok, domain: FixtureDomain.__caravela_domain__()}
  end

  describe "Caravela.Gen.Context - action_access plumbing" do
    test "emits action_access/2 and action_access/3 on the context", %{domain: domain} do
      {_path, src} = Context.render(domain)

      assert src =~ "def action_access(entity, context)"
      assert src =~ "def action_access(entity, record, context)"
      assert src =~ "defp compute_action_access(:books, actor)"
      assert src =~ "defp compute_action_access(:journals, actor)"
    end

    # The generated code gets mix-formatted, so the long arity-3
    # calls wrap across multiple lines. Match with regex that allows
    # arbitrary whitespace between tokens.
    defp compiled_allow_call?(src, entity, action) do
      Regex.match?(
        ~r/__caravela_policy_allow__\(\s*:#{entity},\s*:#{action},\s*actor\s*\)/s,
        src
      )
    end

    test "arity-1 gates compile to arity-3 policy_allow calls", %{domain: domain} do
      {_path, src} = Context.render(domain)

      assert compiled_allow_call?(src, "books", "create")
      assert compiled_allow_call?(src, "books", "delete")
    end

    test "arity-2 gates compile to the :per_record literal", %{domain: domain} do
      {_path, src} = Context.render(domain)

      # `compute_action_access(:journals, actor)` must map :update to
      # the atom :per_record - action_access/3 resolves it per-row.
      assert src =~ ~r/:journals.*?:update\s*=>\s*:per_record/s
    end

    test "unaffected actions fall back to the entity's allow clause", %{domain: domain} do
      {_path, src} = Context.render(domain)

      # :books has no :update gate; entity-level fallback answers.
      assert compiled_allow_call?(src, "books", "update")
    end

    test "entities with no policy block fall back on the domain default", %{domain: domain} do
      {_path, src} = Context.render(domain)

      # :authors has no policy block at all; the compiler's domain
      # default answers through the same arity-3 call.
      assert compiled_allow_call?(src, "authors", "create")
      assert compiled_allow_call?(src, "authors", "update")
      assert compiled_allow_call?(src, "authors", "delete")
    end
  end

  describe "Caravela.Gen.Svelte - Actions TypeScript type" do
    test "emits <Entity>Actions in the shared types file", %{domain: domain} do
      {_path, src} = Svelte.render_types(domain)

      assert src =~ "export interface BookActions"
      assert src =~ "export interface JournalActions"
      assert src =~ "export interface AuthorActions"
    end

    test "arity-1 gates get `boolean`", %{domain: domain} do
      {_path, src} = Svelte.render_types(domain)

      # :books.create (arity-1) must be typed as plain boolean.
      # Pattern matches the specific field inside BookActions block.
      assert src =~ ~r/BookActions\s*\{[^}]*create:\s+boolean;/s
    end

    test "arity-2 gates get `boolean | 'per_record'`", %{domain: domain} do
      {_path, src} = Svelte.render_types(domain)

      # :journals.update (arity-2) must be typed with the per-record
      # disjunction.
      assert src =~ ~r/JournalActions\s*\{[^}]*update:\s+boolean \| 'per_record';/s
    end
  end

  describe "Caravela.Gen.LiveView - passes actions into component props" do
    test "index assigns actions and threads them as a prop", %{domain: domain} do
      {_path, src} =
        LiveView.render_all(domain, root: System.tmp_dir!())
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/index.ex") end)

      assert src =~ "assign(:actions, Fixture_domain.action_access(:books, context))" ||
               src =~ "action_access(:books, context)"

      assert src =~ "actions: @actions"
    end

    test "show resolves per-record actions via action_access/3", %{domain: domain} do
      {_path, src} =
        LiveView.render_all(domain, root: System.tmp_dir!())
        |> Enum.find(fn {p, _} -> String.ends_with?(p, "book_live/show.ex") end)

      assert src =~ "action_access(:books, entity, context)"
      assert src =~ "actions: assigns[:actions] || %{}"
    end
  end

  describe "Caravela.Gen.RestController - passes actions into render/3" do
    test "index threads collection-level actions", %{domain: domain} do
      [{_path, src}] = RestController.render_all(domain, root: System.tmp_dir!())

      assert src =~ "action_access(:journals, context)"
      assert src =~ "actions: actions"
    end

    test "show resolves per-record actions from the loaded entity", %{domain: domain} do
      [{_path, src}] = RestController.render_all(domain, root: System.tmp_dir!())

      assert src =~ "action_access(:journals, entity, context)"
    end

    test "create re-render with errors also ships actions", %{domain: domain} do
      [{_path, src}] = RestController.render_all(domain, root: System.tmp_dir!())

      # The :unprocessable_entity branch should re-render the form
      # with actions, not just field_access.
      assert src =~ "errors: ChangesetTranslator.translate(changeset)"
      assert src =~ "actions: actions"
    end
  end
end
