defmodule Caravela.GenCustomChecksumTest do
  use ExUnit.Case, async: false

  alias Caravela.Gen.Custom

  describe "stamp_header/2 + verify_contents/2 (elixir style)" do
    test "round-trips: stamped content verifies as :ok" do
      body = """
      defmodule MyApp.Library do
        def list_books, do: []

        # --- CUSTOM ---
        # Custom code below this line is preserved on regeneration.
      end
      """

      stamped = Custom.stamp_header(body, generator: :context)
      assert Custom.verify_contents(stamped) == :ok
    end

    test "the header line carries generator, version, and hash" do
      stamped = Custom.stamp_header("defmodule X do\nend\n", generator: :context)
      [first, _] = String.split(stamped, "\n", parts: 2)

      assert {:ok, %{generator: "context", version: v, hash: hash}} =
               Custom.parse_header_line(first)

      assert is_binary(v) and v != ""
      assert String.length(hash) == 64
    end

    test "verify_contents returns :no_header when the file has no header" do
      assert Custom.verify_contents("defmodule Foo do\nend\n") == :no_header
    end

    test "verify_contents flags mismatch when the body above the marker is edited" do
      stamped =
        Custom.stamp_header(
          "defmodule X do\n  def a, do: 1\n\n  # --- CUSTOM ---\nend\n",
          generator: :context
        )

      tampered = String.replace(stamped, "def a, do: 1", "def a, do: 2")

      assert {:mismatch, _stored, _current} = Custom.verify_contents(tampered)
    end

    test "edits BELOW the marker do not change the hash" do
      stamped =
        Custom.stamp_header(
          "defmodule X do\n  def a, do: 1\n\n  # --- CUSTOM ---\nend\n",
          generator: :context
        )

      with_user_code =
        String.replace(
          stamped,
          "# --- CUSTOM ---\nend",
          "# --- CUSTOM ---\n  def user_fn, do: :ok\nend"
        )

      assert Custom.verify_contents(with_user_code) == :ok
    end

    test "stamp_header replaces any pre-existing header line" do
      body = "defmodule X do\nend\n"
      once = Custom.stamp_header(body, generator: :context)
      twice = Custom.stamp_header(once, generator: :context)

      # Exactly one header line survives.
      header_lines =
        twice
        |> String.split("\n")
        |> Enum.filter(&String.starts_with?(&1, "# caravela-gen:"))

      assert length(header_lines) == 1
    end
  end

  describe "stamp_header/2 + verify_contents/2 (ts style)" do
    test "round-trips typescript content" do
      body = """
      export interface Book {
        id: string;
      }

      // --- CUSTOM ---
      """

      stamped = Custom.stamp_header(body, style: :ts, generator: :svelte_types)
      [first | _] = String.split(stamped, "\n")

      assert String.starts_with?(first, "// caravela-gen:")
      assert Custom.verify_contents(stamped, :ts) == :ok
    end
  end

  describe "stamp_header/2 + verify_contents/2 (svelte style)" do
    test "round-trips svelte content with HTML-comment header" do
      body = """
      <script>
        let x = 1;
      </script>

      <!-- --- CUSTOM --- -->
      """

      stamped = Custom.stamp_header(body, style: :svelte, generator: :svelte_index)
      [first | _] = String.split(stamped, "\n")

      assert String.starts_with?(first, "<!-- caravela-gen:")
      assert String.ends_with?(first, "-->")
      assert Custom.verify_contents(stamped, :svelte) == :ok
    end
  end

  describe "verify_existing!/2" do
    setup %{test: name} do
      dir = Path.join(System.tmp_dir!(), "caravela_checksum_#{name}_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test ":ok when the file does not exist", %{dir: dir} do
      assert Custom.verify_existing!(Path.join(dir, "missing.ex")) == :ok
    end

    test ":ok when the file has no Caravela header (first-time adoption)", %{dir: dir} do
      path = Path.join(dir, "legacy.ex")
      File.write!(path, "defmodule Legacy do\nend\n")

      assert Custom.verify_existing!(path) == :ok
    end

    test ":ok when stored and current hashes match", %{dir: dir} do
      path = Path.join(dir, "ok.ex")

      source =
        Custom.stamp_header(
          "defmodule Ok do\n  # --- CUSTOM ---\nend\n",
          generator: :context
        )

      File.write!(path, source)

      assert Custom.verify_existing!(path) == :ok
    end

    test "raises Mix error when hashes differ and :force is not set", %{dir: dir} do
      path = Path.join(dir, "tampered.ex")

      source =
        Custom.stamp_header(
          "defmodule T do\n  def a, do: 1\n  # --- CUSTOM ---\nend\n",
          generator: :context
        )

      File.write!(path, source)
      File.write!(path, String.replace(source, "def a, do: 1", "def a, do: 999"))

      assert_raise Mix.Error, ~r/Caravela detected unexpected changes/, fn ->
        Custom.verify_existing!(path)
      end
    end

    test "returns :ok with a warning when hashes differ and :force is true", %{dir: dir} do
      path = Path.join(dir, "forced.ex")

      source =
        Custom.stamp_header(
          "defmodule F do\n  def a, do: 1\n  # --- CUSTOM ---\nend\n",
          generator: :context
        )

      File.write!(path, source)
      File.write!(path, String.replace(source, "def a, do: 1", "def a, do: 999"))

      # Capture Mix shell so we don't spam test output
      Mix.shell(Mix.Shell.Process)

      assert Custom.verify_existing!(path, force: true) == :ok

      assert_receive {:mix_shell, :info, [iodata]}
      flat = IO.iodata_to_binary(iodata)
      assert flat =~ "--force overriding checksum mismatch"
    after
      Mix.shell(Mix.Shell.IO)
    end
  end

  describe "merge_with_file/3" do
    setup %{test: name} do
      dir = Path.join(System.tmp_dir!(), "caravela_merge_#{name}_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "preserves user code below the marker AND verifies the header", %{dir: dir} do
      path = Path.join(dir, "ctx.ex")

      v1 =
        Custom.stamp_header(
          """
          defmodule Ctx do
            def old_gen, do: :v1

            # --- CUSTOM ---
            # Custom code below this line is preserved on regeneration.
          end
          """,
          generator: :context
        )

      # First write, plus user appends below the marker.
      with_user_code = String.replace(v1, "# Custom code below this line is preserved on regeneration.\n", "# Custom code below this line is preserved on regeneration.\n  def my_helper, do: :kept\n")
      File.write!(path, with_user_code)

      regenerated_template = """
      defmodule Ctx do
        def new_gen, do: :v2

        # --- CUSTOM ---
        # Custom code below this line is preserved on regeneration.
      end
      """

      merged = Custom.merge_with_file(regenerated_template, path)

      assert merged =~ "def new_gen, do: :v2"
      refute merged =~ "def old_gen, do: :v1"
      assert merged =~ "def my_helper, do: :kept"
    end

    test "raises Mix error when the on-disk file has a header mismatch (no force)", %{dir: dir} do
      path = Path.join(dir, "mismatch.ex")

      good =
        Custom.stamp_header(
          """
          defmodule M do
            def a, do: 1
            # --- CUSTOM ---
          end
          """,
          generator: :context
        )

      tampered = String.replace(good, "def a, do: 1", "def a, do: 999")
      File.write!(path, tampered)

      assert_raise Mix.Error, fn ->
        Custom.merge_with_file("defmodule M do\nend\n", path)
      end
    end

    test "force: true bypasses verification and uses the new source", %{dir: dir} do
      path = Path.join(dir, "forced.ex")

      good =
        Custom.stamp_header(
          """
          defmodule F do
            def a, do: 1
            # --- CUSTOM ---
          end
          """,
          generator: :context
        )

      tampered = String.replace(good, "def a, do: 1", "def a, do: 999")
      File.write!(path, tampered)

      Mix.shell(Mix.Shell.Process)

      fresh =
        """
        defmodule F do
          def b, do: 2
          # --- CUSTOM ---
        end
        """

      merged = Custom.merge_with_file(fresh, path, force: true)

      assert merged =~ "def b, do: 2"
      # A force warning was emitted
      assert_receive {:mix_shell, :info, [_]}
    after
      Mix.shell(Mix.Shell.IO)
    end
  end

  describe "named CUSTOM blocks" do
    test "named_empty/2 renders a marker pair" do
      assert Custom.named_empty(:list_books) ==
               "  # --- CUSTOM :list_books ---\n  # --- END :list_books ---"
    end

    test "named_empty/2 respects a custom indent" do
      assert Custom.named_empty(:foo, indent: "") ==
               "# --- CUSTOM :foo ---\n# --- END :foo ---"
    end

    test "extract_named_blocks/1 returns a name => body map" do
      source = """
      defmodule X do
        def a, do: 1
        # --- CUSTOM :a ---
        def a_helper, do: :ok
        # --- END :a ---

        def b, do: 2
        # --- CUSTOM :b ---
        # --- END :b ---
      end
      """

      blocks = Custom.extract_named_blocks(source)

      assert Map.has_key?(blocks, "a")
      assert Map.has_key?(blocks, "b")
      assert blocks["a"] =~ "def a_helper, do: :ok"
      assert blocks["b"] == ""
    end

    test "extract_named_blocks/1 ignores unmatched or malformed markers" do
      source = """
      # --- CUSTOM :orphan_open ---
      no closing marker
      """

      assert Custom.extract_named_blocks(source) == %{}
    end

    test "merge_named/3 swaps in existing content for matching block names" do
      new_source = """
      defmodule X do
        def a, do: 1
        # --- CUSTOM :a ---
        # --- END :a ---
      end
      """

      existing = """
      defmodule X do
        def a, do: 1
        # --- CUSTOM :a ---
        def a_helper, do: :kept
        # --- END :a ---
      end
      """

      merged = Custom.merge_named(new_source, existing)
      assert merged =~ "def a_helper, do: :kept"
    end

    test "merge_named/3 leaves blocks without existing content alone" do
      new_source = """
      # --- CUSTOM :new_block ---
      # --- END :new_block ---
      """

      existing = "defmodule Untouched do\nend\n"

      assert Custom.merge_named(new_source, existing) == new_source
    end

    test "merge_named/3 warns on orphan blocks" do
      Mix.shell(Mix.Shell.Process)

      new_source = "nothing here\n"

      existing = """
      # --- CUSTOM :departed ---
      body the generator no longer emits
      # --- END :departed ---
      """

      Custom.merge_named(new_source, existing)

      assert_receive {:mix_shell, :info, [iodata]}
      assert IO.iodata_to_binary(iodata) =~ "orphan CUSTOM blocks"
      assert IO.iodata_to_binary(iodata) =~ "departed"
    after
      Mix.shell(Mix.Shell.IO)
    end

    test "merge_named/3 is a no-op for non-elixir styles" do
      new_source = "// --- CUSTOM :x ---\n// --- END :x ---"
      existing = "different content"

      assert Custom.merge_named(new_source, existing, style: :ts) == new_source
    end

    test "edits inside a named block do NOT change the checksum" do
      base =
        Custom.stamp_header(
          """
          defmodule X do
            def a, do: 1
            # --- CUSTOM :a ---
            # --- END :a ---

            # --- CUSTOM ---
          end
          """,
          generator: :context
        )

      edited_in_block =
        String.replace(
          base,
          "# --- CUSTOM :a ---\n",
          "# --- CUSTOM :a ---\n  def user_helper, do: :ok\n"
        )

      # The whole file has a new sha256 on content (because user added
      # a line), but the checksum header is computed over the
      # *normalised* content with named-block bodies empty. So the
      # stored header hash should still match.
      assert Custom.verify_contents(edited_in_block) == :ok
    end

    test "edits OUTSIDE named blocks DO change the checksum" do
      base =
        Custom.stamp_header(
          """
          defmodule X do
            def a, do: 1
            # --- CUSTOM :a ---
            # --- END :a ---

            # --- CUSTOM ---
          end
          """,
          generator: :context
        )

      # Change a function body above the marker, outside any named block.
      tampered = String.replace(base, "def a, do: 1", "def a, do: 999")

      assert {:mismatch, _stored, _current} = Custom.verify_contents(tampered)
    end

    test "deleting a named block's markers DOES change the checksum" do
      base =
        Custom.stamp_header(
          """
          defmodule X do
            def a, do: 1
            # --- CUSTOM :a ---
            # --- END :a ---

            # --- CUSTOM ---
          end
          """,
          generator: :context
        )

      stripped =
        base
        |> String.replace("  # --- CUSTOM :a ---\n  # --- END :a ---\n", "")

      assert {:mismatch, _stored, _current} = Custom.verify_contents(stripped)
    end
  end

  describe "end-to-end with a real generator" do
    alias Caravela.Gen.Context

    setup %{test: name} do
      dir = Path.join(System.tmp_dir!(), "caravela_e2e_#{name}_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      domain = MyApp.Domains.Library.__caravela_domain__()
      {:ok, dir: dir, domain: domain}
    end

    test "Context.render stamps a header and can verify its own output", %{
      dir: dir,
      domain: domain
    } do
      {rel, source} = Context.render(domain, root: dir)
      target = Path.join(dir, rel)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, source)

      # Read back, verify header.
      on_disk = File.read!(target)
      assert Custom.verify_contents(on_disk) == :ok

      # First line is the generator's header.
      [first_line | _] = String.split(on_disk, "\n")
      assert {:ok, %{generator: "context"}} = Custom.parse_header_line(first_line)
    end

    test "regen after a tampered-above-marker edit raises without --force", %{
      dir: dir,
      domain: domain
    } do
      {rel, source_v1} = Context.render(domain, root: dir)
      target = Path.join(dir, rel)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, source_v1)

      # User edits something above the marker.
      tampered =
        String.replace(source_v1, "def list_books", "def list_my_books")

      File.write!(target, tampered)

      # Regenerating without --force aborts.
      assert_raise Mix.Error, fn ->
        Context.render(domain, root: dir)
      end
    end

    test "regen preserves user code inside a per-function CUSTOM block", %{
      dir: dir,
      domain: domain
    } do
      {rel, source_v1} = Context.render(domain, root: dir)
      target = Path.join(dir, rel)
      File.mkdir_p!(Path.dirname(target))

      # Insert a user helper inside the :list_books named block.
      with_user_code =
        String.replace(
          source_v1,
          "  # --- CUSTOM :list_books ---\n  # --- END :list_books ---",
          "  # --- CUSTOM :list_books ---\n  defp user_helper, do: :kept\n  # --- END :list_books ---"
        )

      File.write!(target, with_user_code)

      # Regen (no --force). Should not raise since the named-block
      # edit doesn't affect the normalised hash.
      {^rel, source_v2} = Context.render(domain, root: dir)

      assert source_v2 =~ "defp user_helper, do: :kept",
             "per-function CUSTOM block lost the user's helper"

      # Verifies cleanly as a round-trip.
      assert Custom.verify_contents(source_v2) == :ok
    end

    test "regen after tampering succeeds with force: true", %{dir: dir, domain: domain} do
      {rel, source_v1} = Context.render(domain, root: dir)
      target = Path.join(dir, rel)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, source_v1)

      tampered = String.replace(source_v1, "def list_books", "def list_my_books")
      File.write!(target, tampered)

      Mix.shell(Mix.Shell.Process)

      {^rel, source_v2} = Context.render(domain, root: dir, force: true)

      # Regen wins: the original function name comes back.
      assert source_v2 =~ "def list_books"
      refute source_v2 =~ "def list_my_books"
    after
      Mix.shell(Mix.Shell.IO)
    end
  end
end
