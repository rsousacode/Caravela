defmodule Caravela.Gen.Custom do
  @moduledoc """
  Preserves user-authored code across regenerations.

  Generators emit a language-appropriate `CUSTOM` marker before the
  closing of every regenerable file. Anything the developer writes
  below that marker is preserved verbatim when the generator runs
  again.

  Caravela also stamps a checksum header at the top of every generated
  file:

      # caravela-gen: generator=context version=0.8.0 above_sha256=<hex>

  On regeneration the checksum is re-computed from the file on disk.
  If the content *above* the marker was edited by hand, the hashes no
  longer match and `verify_existing!/2` aborts via `Mix.raise/1` — the
  user's edits would otherwise be silently overwritten. Pass
  `force: true` (from the mix task's `--force` flag) to bypass.

  Three comment styles are supported via the `:style` opt:

    * `:elixir` (default) — `# …`
    * `:ts` — `// …` (TypeScript)
    * `:svelte` — `<!-- … -->` (HTML/Svelte top-level)
  """

  @header_prefix "caravela-gen:"

  @styles %{
    elixir: %{
      marker: "# --- CUSTOM ---",
      header_open: "# ",
      header_close: ""
    },
    ts: %{
      marker: "// --- CUSTOM ---",
      header_open: "// ",
      header_close: ""
    },
    svelte: %{
      marker: "<!-- --- CUSTOM --- -->",
      header_open: "<!-- ",
      header_close: " -->"
    }
  }

  # Matches a named Elixir CUSTOM block:
  #
  #   # --- CUSTOM :list_books ---
  #   def my_helper, do: :ok
  #   # --- END :list_books ---
  #
  # Group 1 = block name. Group 2 = body (everything between the
  # opening and closing markers). The `/s` flag lets `.` span
  # newlines; the backref `\1` requires the names to match.
  @named_regex ~r/^[ \t]*# --- CUSTOM :([a-zA-Z_][a-zA-Z0-9_!?]*) ---[ \t]*\n(.*?)^[ \t]*# --- END :\1 ---[ \t]*$/ms

  @typedoc "Comment style for a generated file's CUSTOM markers."
  @type style :: :elixir | :ts | :svelte

  @doc "Marker string for the given style (default `:elixir`)."
  @spec marker(style()) :: String.t()
  def marker(style \\ :elixir), do: style_map(style).marker

  @doc """
  Reusable marker block appended by Elixir generators. Terminates the
  module with `end` once custom content is merged in. Only meaningful
  for the `:elixir` style; Svelte and TS templates embed their own
  trailing marker inline.
  """
  @spec marker_block() :: String.t()
  def marker_block do
    marker(:elixir) <>
      "\n  # Custom code below this line is preserved on regeneration." <>
      "\nend\n"
  end

  @doc """
  Empty named CUSTOM block, rendered at its extension point by
  generator templates. The `indent` opt controls leading whitespace.

  ## Example

      iex> Caravela.Gen.Custom.named_empty(:list_books, indent: "  ")
      "  # --- CUSTOM :list_books ---\\n  # --- END :list_books ---"
  """
  @spec named_empty(atom() | String.t(), keyword()) :: String.t()
  def named_empty(name, opts \\ []) when is_atom(name) or is_binary(name) do
    indent = Keyword.get(opts, :indent, "  ")
    n = to_string(name)

    "#{indent}# --- CUSTOM :#{n} ---\n" <>
      "#{indent}# --- END :#{n} ---"
  end

  @doc """
  Extract all named CUSTOM blocks from an Elixir source. Returns
  `%{name => body}` where name is a binary and body is the raw text
  between the `CUSTOM :name` and `END :name` markers.

  Only parses Elixir-style markers (`# --- CUSTOM :name ---`). The
  other styles don't support named blocks in this release.
  """
  @spec extract_named_blocks(String.t()) :: %{String.t() => String.t()}
  def extract_named_blocks(source) when is_binary(source) do
    @named_regex
    |> Regex.scan(source)
    |> Enum.map(fn [_full, name, body] -> {name, body} end)
    |> Map.new()
  end

  @doc """
  Merge named CUSTOM blocks from `existing_source` into `new_source`.

  For every named block in `new_source`, if `existing_source` has a
  block with the same name, the new source's body is replaced with
  the existing body. Orphan blocks (present in existing but absent
  in new) are reported via `Mix.shell/0` and discarded.

  Only applies to Elixir-style markers. Returns `new_source`
  unchanged for any other style.
  """
  @spec merge_named(String.t(), String.t(), keyword()) :: String.t()
  def merge_named(new_source, existing_source, opts \\ [])

  def merge_named(new_source, existing_source, opts)
      when is_binary(new_source) and is_binary(existing_source) do
    case Keyword.get(opts, :style, :elixir) do
      :elixir -> do_merge_named(new_source, existing_source)
      _ -> new_source
    end
  end

  defp do_merge_named(new_source, existing_source) do
    existing_blocks = extract_named_blocks(existing_source)
    new_blocks = extract_named_blocks(new_source)

    orphans = Map.drop(existing_blocks, Map.keys(new_blocks))

    if map_size(orphans) > 0, do: warn_orphans(orphans)

    Regex.replace(@named_regex, new_source, fn full, name, _new_body ->
      case Map.fetch(existing_blocks, name) do
        {:ok, existing_body} -> rebuild_named_block(full, name, existing_body)
        :error -> full
      end
    end)
  end

  # Preserve the exact indentation of the opening marker line captured
  # by `full`, so the rebuilt block keeps its place in the file.
  defp rebuild_named_block(full, name, body) do
    [first_line | _] = String.split(full, "\n", parts: 2)
    indent = leading_whitespace(first_line)

    "#{first_line}\n#{body}#{indent}# --- END :#{name} ---"
  end

  defp leading_whitespace(line) do
    case Regex.run(~r/^[ \t]*/, line) do
      [ws] -> ws
      _ -> ""
    end
  end

  @doc """
  Merge custom content from an existing source into a newly-generated
  source. If the existing source does not contain the marker, the new
  source is returned unchanged.

  Splits on the **last** occurrence of the marker in both sources.
  This is deliberate: the marker string commonly appears inside
  `@moduledoc` / `<!-- -->` prose where it is being *named* rather
  than delimiting user code. The real marker is always the last one
  (emitted at the tail of the template). Using first-occurrence
  would cut the file at the docstring and produce garbage.
  """
  @spec merge(String.t(), String.t(), keyword()) :: String.t()
  def merge(new_source, existing_source, opts \\ [])
      when is_binary(new_source) and is_binary(existing_source) do
    style = Keyword.get(opts, :style, :elixir)
    marker = marker(style)
    existing_source = strip_header(existing_source, style)

    case split_on_last(existing_source, marker) do
      {:ok, _existing_above, existing_below} ->
        case split_on_last(new_source, marker) do
          {:ok, new_above, _new_below} -> new_above <> marker <> existing_below
          :no_marker -> new_source
        end

      :no_marker ->
        new_source
    end
  end

  @doc """
  Merge custom content from disk, after verifying the on-disk file
  has not been tampered with above the marker.

  `opts`:
    * `:style` (default `:elixir`) — `:elixir | :ts | :svelte`.
    * `:force` (default false) — skip the verification step.

  Raises via `Mix.raise/1` when the file's stored checksum does not
  match its current above-marker body and `force: true` was not
  passed. Returns the merged source otherwise.
  """
  @spec merge_with_file(String.t(), Path.t(), keyword()) :: String.t()
  def merge_with_file(new_source, path, opts \\ []) do
    verify_existing!(path, opts)

    case File.read(path) do
      {:ok, existing} ->
        new_source
        |> merge_named(existing, opts)
        |> merge(existing, opts)

      {:error, _} ->
        new_source
    end
  end

  @doc """
  Stamp a fresh `caravela-gen:` header onto `source`, replacing any
  existing header line on the first line.

  `opts`:
    * `:generator` (required) — atom identifying the generator.
    * `:style` (default `:elixir`) — comment style for the header.
    * `:version` — override the default Caravela version string.

  The checksum covers every byte above the CUSTOM marker, excluding
  the header line itself. Call after any formatting step so the hash
  reflects the bytes actually written to disk.
  """
  @spec stamp_header(String.t(), keyword()) :: String.t()
  def stamp_header(source, opts) when is_binary(source) do
    generator = Keyword.fetch!(opts, :generator)
    version = Keyword.get(opts, :version, caravela_version())
    style = Keyword.get(opts, :style, :elixir)

    body = strip_header(source, style)
    hash = compute_above_marker_hash(body, style)
    header_line(style, generator, version, hash) <> body
  end

  @doc """
  Verify `path`'s on-disk content against the checksum stored in its
  `caravela-gen:` header. Returns `:ok` when:

    * the file does not exist;
    * the file has no Caravela header (first-time adoption);
    * the file has a header and the stored hash matches the current
      above-marker body.

  Raises via `Mix.raise/1` when the stored hash does not match, unless
  `opts[:force]` is true.
  """
  @spec verify_existing!(Path.t(), keyword()) :: :ok
  def verify_existing!(path, opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    style = Keyword.get(opts, :style, :elixir)

    case File.read(path) do
      {:error, _} ->
        :ok

      {:ok, contents} ->
        case verify_contents(contents, style) do
          :ok ->
            :ok

          :no_header ->
            :ok

          {:mismatch, stored, current} when force? ->
            warn_forced(path, stored, current)

          {:mismatch, stored, current} ->
            Mix.raise(mismatch_message(path, stored, current, style))
        end
    end
  end

  @doc """
  Inspect source contents. Returns `:ok`, `:no_header`, or
  `{:mismatch, stored_hash, current_hash}`.

  Pure function. Useful from tests and `mix caravela.gen --check`.
  """
  @spec verify_contents(String.t(), style()) ::
          :ok | :no_header | {:mismatch, String.t(), String.t()}
  def verify_contents(contents, style \\ :elixir) when is_binary(contents) do
    case split_first_line(contents) do
      {first, rest} ->
        if header_line?(first, style) do
          case parse_header_line(first, style) do
            {:ok, %{hash: stored}} ->
              current = compute_above_marker_hash(rest, style)
              if stored == current, do: :ok, else: {:mismatch, stored, current}

            :error ->
              :no_header
          end
        else
          :no_header
        end

      :no_newline ->
        :no_header
    end
  end

  @doc """
  Parse a header line into `{:ok, %{generator, version, hash}}` or
  `:error`. Exposed for tests and tooling.
  """
  @spec parse_header_line(String.t(), style()) ::
          {:ok, %{hash: String.t(), generator: String.t() | nil, version: String.t() | nil}}
          | :error
  def parse_header_line(line, style \\ :elixir) when is_binary(line) do
    %{header_open: open, header_close: close} = style_map(style)

    body =
      line
      |> String.replace_prefix(open <> @header_prefix, "")
      |> String.replace_suffix(close, "")
      |> String.trim()

    if body == line do
      :error
    else
      pairs =
        body
        |> String.split(~r/\s+/, trim: true)
        |> Enum.flat_map(fn kv ->
          case String.split(kv, "=", parts: 2) do
            [k, v] -> [{k, v}]
            _ -> []
          end
        end)
        |> Map.new()

      case pairs do
        %{"above_sha256" => hash} when hash != "" ->
          {:ok,
           %{
             hash: hash,
             generator: Map.get(pairs, "generator"),
             version: Map.get(pairs, "version")
           }}

        _ ->
          :error
      end
    end
  end

  # --- Internals ----------------------------------------------------------

  defp style_map(style) when is_map_key(@styles, style), do: Map.fetch!(@styles, style)

  defp style_map(style),
    do:
      raise(
        ArgumentError,
        "unknown CUSTOM style #{inspect(style)}; expected :elixir | :ts | :svelte"
      )

  defp header_line(style, generator, version, hash) do
    %{header_open: open, header_close: close} = style_map(style)

    body = "#{@header_prefix} generator=#{generator} version=#{version} above_sha256=#{hash}"
    open <> body <> close <> "\n"
  end

  defp header_line?(line, style) do
    %{header_open: open} = style_map(style)
    String.starts_with?(line, open <> @header_prefix)
  end

  defp strip_header(source, style) do
    case split_first_line(source) do
      {first, rest} -> if header_line?(first, style), do: rest, else: source
      :no_newline -> source
    end
  end

  defp split_first_line(source) do
    case String.split(source, "\n", parts: 2) do
      [first, rest] -> {first, rest}
      _ -> :no_newline
    end
  end

  defp compute_above_marker_hash(source, style) do
    marker = marker(style)

    above =
      case split_on_last(source, marker) do
        {:ok, a, _} -> a
        :no_marker -> source
      end

    # Named-block bodies are user territory — normalise them to empty
    # before hashing so edits inside a block don't trigger a mismatch.
    # Edits that add, remove, or rename markers *do* change the hash.
    normalized = normalize_for_hash(above, style)
    :crypto.hash(:sha256, normalized) |> Base.encode16(case: :lower)
  end

  defp normalize_for_hash(source, :elixir) do
    Regex.replace(@named_regex, source, fn full, name, _body ->
      rebuild_named_block(full, name, "")
    end)
  end

  defp normalize_for_hash(source, _style), do: source

  # Split a binary on the LAST occurrence of `marker`. Returns
  # `{:ok, above, below}` or `:no_marker`. See the moduledoc for `merge/3`
  # for why the last occurrence is load-bearing.
  defp split_on_last(source, marker) do
    case :binary.matches(source, marker) do
      [] ->
        :no_marker

      matches ->
        {pos, len} = List.last(matches)
        above = :binary.part(source, 0, pos)
        below = :binary.part(source, pos + len, byte_size(source) - pos - len)
        {:ok, above, below}
    end
  end

  defp caravela_version do
    case Application.spec(:caravela, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end

  defp warn_forced(path, stored, current) do
    Mix.shell().info([
      IO.ANSI.yellow(),
      "warning: --force overriding checksum mismatch on #{path}\n",
      "  stored:  #{stored}\n",
      "  current: #{current}\n",
      "  user edits above the CUSTOM marker will be overwritten.",
      IO.ANSI.reset()
    ])

    :ok
  end

  defp warn_orphans(orphans) do
    names = Enum.map_join(orphans, "\n", fn {name, _} -> "    :#{name}" end)

    Mix.shell().info([
      IO.ANSI.yellow(),
      "warning: orphan CUSTOM blocks dropped during regen:\n",
      names,
      "\n  These named blocks no longer have a home in the generator output.\n",
      "  Recover from git history if you need the content.",
      IO.ANSI.reset()
    ])
  end

  defp mismatch_message(path, stored, current, style) do
    m = marker(style)

    """

    Caravela detected unexpected changes above the `#{m}` marker in:

      #{path}

    That region is regenerated from your domain module on every run.
    Your edits would be overwritten, so the generator aborted.

      stored hash:  #{stored}
      current hash: #{current}

    What to do:

      1. If the edits are intentional, move them BELOW the `#{m}`
         marker (the user-code zone) and re-run the generator.

      2. If you want Caravela's version back (discarding the edits above
         the marker), re-run with `--force`.

      3. To inspect what Caravela wants to write first, re-run with
         `--dry-run`.
    """
  end
end
