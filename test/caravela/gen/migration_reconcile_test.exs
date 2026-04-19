defmodule Caravela.Gen.MigrationReconcileTest do
  use ExUnit.Case, async: true

  alias Caravela.Gen.Migration

  defmodule LibraryDomain do
    use Caravela.Domain, default_policy: :allow

    entity :books do
      field :title, :string, required: true
    end
  end

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "caravela_migration_reconcile_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(tmp, "priv/repo/migrations"))
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, root: tmp}
  end

  defp touch(root, basename) do
    File.write!(Path.join([root, "priv/repo/migrations", basename]), "# placeholder")
    basename
  end

  describe "reconcile_timestamp/2" do
    test "returns a fresh timestamp when no prior migration exists", %{root: root} do
      {ts, duplicates} = Migration.reconcile_timestamp(LibraryDomain.__caravela_domain__(), root)

      assert Regex.match?(~r/^\d{14}$/, ts)
      assert duplicates == []
    end

    test "reuses the existing migration's timestamp when one matches", %{root: root} do
      existing = touch(root, "20260101000000_create_library_domain_tables.exs")

      {ts, duplicates} = Migration.reconcile_timestamp(LibraryDomain.__caravela_domain__(), root)

      assert ts == "20260101000000"
      assert duplicates == []

      # Confirmed the render path uses that timestamp, so a regenerated
      # file would overwrite the existing one rather than creating a
      # sibling.
      {path, _src} = Migration.render(LibraryDomain.__caravela_domain__(), timestamp: ts)
      assert Path.basename(path) == existing
    end

    test "picks the oldest timestamp and surfaces the rest as duplicates", %{root: root} do
      oldest = touch(root, "20260101000000_create_library_domain_tables.exs")
      _mid = touch(root, "20260201000000_create_library_domain_tables.exs")
      _newest = touch(root, "20260301000000_create_library_domain_tables.exs")

      {ts, duplicates} = Migration.reconcile_timestamp(LibraryDomain.__caravela_domain__(), root)

      assert ts == "20260101000000"

      assert duplicates == [
               "20260201000000_create_library_domain_tables.exs",
               "20260301000000_create_library_domain_tables.exs"
             ]

      # The surviving migration (which the caller would overwrite) is
      # still the oldest one.
      {path, _src} = Migration.render(LibraryDomain.__caravela_domain__(), timestamp: ts)
      assert Path.basename(path) == oldest
    end

    test "ignores migrations whose stem doesn't match the domain", %{root: root} do
      touch(root, "20260101000000_create_catalog_tables.exs")
      touch(root, "20260102000000_add_index_to_books.exs")

      {ts, duplicates} = Migration.reconcile_timestamp(LibraryDomain.__caravela_domain__(), root)

      assert Regex.match?(~r/^\d{14}$/, ts)
      assert duplicates == []
    end

    test "ignores malformed timestamps in the migrations dir", %{root: root} do
      # A manually-renamed or developer-tweaked file with a short
      # prefix must not be confused with a create-tables migration.
      touch(root, "12345_create_library_domain_tables.exs")

      {ts, duplicates} = Migration.reconcile_timestamp(LibraryDomain.__caravela_domain__(), root)

      assert Regex.match?(~r/^\d{14}$/, ts)
      assert duplicates == []
    end

    test "handles a missing migrations directory without raising", %{root: root} do
      File.rm_rf!(Path.join(root, "priv/repo/migrations"))

      {ts, duplicates} = Migration.reconcile_timestamp(LibraryDomain.__caravela_domain__(), root)

      assert Regex.match?(~r/^\d{14}$/, ts)
      assert duplicates == []
    end
  end

  describe "existing_migration_basename/2" do
    test "returns nil when no matching migration is present", %{root: root} do
      refute Migration.existing_migration_basename(LibraryDomain.__caravela_domain__(), root)
    end

    test "returns the basename when one match exists", %{root: root} do
      name = touch(root, "20260101000000_create_library_domain_tables.exs")

      assert Migration.existing_migration_basename(LibraryDomain.__caravela_domain__(), root) ==
               name
    end

    test "returns the oldest when multiple matches exist", %{root: root} do
      oldest = touch(root, "20260101000000_create_library_domain_tables.exs")
      touch(root, "20260201000000_create_library_domain_tables.exs")

      assert Migration.existing_migration_basename(LibraryDomain.__caravela_domain__(), root) ==
               oldest
    end
  end
end
