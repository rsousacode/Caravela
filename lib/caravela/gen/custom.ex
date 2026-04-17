defmodule Caravela.Gen.Custom do
  @moduledoc """
  Preserves user-authored code across regenerations.

  Generators emit a `# --- CUSTOM ---` marker before the closing `end`
  of every regenerable module. Anything the developer writes below that
  marker in the generated file is preserved verbatim when the generator
  runs again.
  """

  @marker "# --- CUSTOM ---"

  @doc "The marker string."
  def marker, do: @marker

  @doc """
  Reusable marker block appended by generators. Terminates the module
  with `end` once custom content is merged in.
  """
  def marker_block do
    @marker <>
      "\n  # Custom code below this line is preserved on regeneration." <>
      "\nend\n"
  end

  @doc """
  Merge custom content from an existing file into a newly-generated
  source. If the existing file does not contain the marker, the new
  source is returned unchanged.
  """
  def merge(new_source, existing_source)
      when is_binary(new_source) and is_binary(existing_source) do
    case String.split(existing_source, @marker, parts: 2) do
      [_, rest] ->
        case String.split(new_source, @marker, parts: 2) do
          [head, _] -> head <> @marker <> rest
          _ -> new_source
        end

      _ ->
        new_source
    end
  end

  @doc """
  Merge custom content from disk. Reads `path` if it exists; otherwise
  returns the generated source unchanged.
  """
  def merge_with_file(new_source, path) do
    case File.read(path) do
      {:ok, existing} -> merge(new_source, existing)
      {:error, _} -> new_source
    end
  end
end
