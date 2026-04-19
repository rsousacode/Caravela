defmodule Mix.Tasks.Caravela.Info do
  @shortdoc "Print a human-readable summary of a Caravela domain"

  @moduledoc """
  Print a terminal-friendly summary of a compiled Caravela domain —
  domain-level flags, every entity's fields / relations / policy /
  auth config, and top-level counts.

      mix caravela.info MyApp.Domains.Library

  Intended for humans scanning "what's in this domain?" at a glance.
  For a machine-readable dump, use `mix caravela.ir` instead.

  Flags:

    * `--no-color` — disable ANSI colors (useful for CI / piping)
  """

  use Mix.Task

  alias Caravela.{IR, MixHelpers}

  @switches [color: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)
    domain = MixHelpers.load_domain!(args)
    color? = Keyword.get(opts, :color, IO.ANSI.enabled?())
    ir = IR.of(domain)

    Mix.shell().info(render(ir, color?))
    :ok
  end

  @doc """
  Render an IR map as a terminal-friendly string. Exposed for tests
  and other tooling that wants the same output without invoking the
  mix task.
  """
  @spec render(map(), boolean()) :: String.t()
  def render(ir, color? \\ false) when is_map(ir) do
    [
      header(ir, color?),
      "\n",
      domain_flags(ir),
      "\n\n",
      entities_section(ir, color?),
      "\n",
      totals(ir)
    ]
    |> IO.iodata_to_binary()
  end

  # --- Header + flags ---------------------------------------------------

  defp header(ir, color?) do
    name = colorize(ir.domain, :bold, color?)
    "#{name}  @ Caravela #{ir.caravela_version}"
  end

  defp domain_flags(ir) do
    """

      multi-tenant:   #{yn(ir.multi_tenant)}
      default policy: #{ir.default_policy}
      api version:    #{ir.version || "—"}\
    """
  end

  # --- Entities ---------------------------------------------------------

  defp entities_section(ir, color?) do
    count = length(ir.entities)
    header = colorize("Entities (#{count})", :bold, color?)

    body =
      ir.entities
      |> Enum.map(&render_entity(&1, ir, color?))
      |> Enum.join("\n\n")

    "#{header}\n\n#{body}"
  end

  defp render_entity(e, ir, color?) do
    name = colorize(e.name, :cyan, color?)

    [
      "  #{name}\n",
      pad("module:", e.module),
      pad("table:", e.table),
      field_section(e.fields),
      relations_section(e, ir),
      policy_section(e),
      auth_section(e)
    ]
    |> IO.iodata_to_binary()
  end

  defp pad(label, value) do
    "    #{String.pad_trailing(label, 12)}#{value}\n"
  end

  # --- Fields -----------------------------------------------------------

  defp field_section([]), do: "    fields:     —\n"

  defp field_section([first | rest]) do
    first_line = "    fields:     " <> render_field(first) <> "\n"

    rest_lines =
      Enum.map_join(rest, "", fn f -> "                " <> render_field(f) <> "\n" end)

    first_line <> rest_lines
  end

  defp render_field(f) do
    bits = [f.type]
    bits = if f.required, do: bits ++ ["required"], else: bits

    bits =
      case f.opts do
        m when map_size(m) == 0 ->
          bits

        m ->
          extra =
            m
            |> Enum.sort()
            |> Enum.map(fn {k, v} -> "#{k}=#{inspect_compact(v)}" end)

          bits ++ extra
      end

    "#{f.name} (#{Enum.join(bits, ", ")})"
  end

  defp inspect_compact(v) when is_binary(v), do: v
  defp inspect_compact(v), do: inspect(v)

  # --- Relations --------------------------------------------------------

  defp relations_section(entity, ir) do
    relevant =
      Enum.filter(ir.relations, fn r ->
        r.from == entity.name or r.to == entity.name
      end)

    case relevant do
      [] ->
        "    relations:  —\n"

      [first | rest] ->
        "    relations:  " <>
          render_relation(first, entity) <>
          "\n" <>
          Enum.map_join(rest, "", fn r ->
            "                " <> render_relation(r, entity) <> "\n"
          end)
    end
  end

  defp render_relation(r, entity) do
    # Show the relation from the entity's perspective. When the entity
    # is the `to` side of the declared relation, flip the kind so the
    # reader sees the inverse view.
    case {r.from == entity.name, r.kind} do
      {true, kind} -> "#{kind} → #{r.to}"
      {false, "has_many"} -> "belongs_to → #{r.from}"
      {false, "has_one"} -> "belongs_to → #{r.from}"
      {false, "belongs_to"} -> "has_many → #{r.from}"
      {false, kind} -> "#{kind} → #{r.from}"
    end
  end

  # --- Policy -----------------------------------------------------------

  defp policy_section(%{policy: nil}), do: "    policy:     —\n"

  defp policy_section(%{policy: p}) do
    parts = []
    parts = if p.has_scope, do: parts ++ ["scope ✓"], else: parts

    gates = length(p.action_gates)
    parts = if gates > 0, do: parts ++ ["#{gates} action gate(s)"], else: parts

    rules = length(p.field_rules)
    parts = if rules > 0, do: parts ++ ["#{rules} field rule(s)"], else: parts

    summary = if parts == [], do: "empty", else: Enum.join(parts, ", ")
    "    policy:     #{summary}\n"
  end

  # --- Auth -------------------------------------------------------------

  defp auth_section(%{auth: nil}), do: "    auth:       —\n"

  defp auth_section(%{auth: auth}) do
    strategies = auth.strategies |> Enum.map(& &1.kind) |> Enum.join(", ")
    hooks = [auth.on_register && "on_register", auth.on_login && "on_login"] |> Enum.filter(& &1)

    extras =
      [
        if(auth.session, do: "session"),
        if(auth.confirm, do: "confirm"),
        if(auth.reset, do: "reset"),
        if(hooks != [], do: "hooks: #{Enum.join(hooks, "+")}")
      ]
      |> Enum.filter(& &1)

    line =
      case extras do
        [] -> strategies
        _ -> strategies <> " · " <> Enum.join(extras, ", ")
      end

    "    auth:       #{line}\n"
  end

  # --- Totals -----------------------------------------------------------

  defp totals(ir) do
    hooks = length(ir.hooks)
    relations = length(ir.relations)

    "\nHooks: #{hooks}  ·  Relations: #{relations}\n"
  end

  # --- Color helpers ----------------------------------------------------

  defp yn(true), do: "yes"
  defp yn(false), do: "no"
  defp yn(_), do: "—"

  defp colorize(text, _color, false), do: text

  defp colorize(text, color, true) do
    ansi =
      case color do
        :bold -> IO.ANSI.bright()
        :cyan -> IO.ANSI.cyan() <> IO.ANSI.bright()
        _ -> ""
      end

    ansi <> text <> IO.ANSI.reset()
  end
end
