# Regeneration and the `# --- CUSTOM ---` marker

Every generated file ends with a marker:

```elixir
  # --- CUSTOM ---
  # Custom code below this line is preserved on regeneration.
end
```

Svelte files use `<!-- --- CUSTOM --- -->`; TypeScript files use
`// --- CUSTOM ---`. Same idea, different comment syntax.

Everything **above** the marker is regenerated from the domain IR
every time you run the matching `mix caravela.gen.*` task.
Everything **below** is preserved verbatim.

## What this gets you

- Keep regenerating as the domain evolves. Add a field, re-run the
  generator, confirm the diff matches your expectations, done.
- Put hand-written CRUD helpers, custom validations, or extra
  `handle_event` clauses below the marker. They survive re-runs.
- Use `--dry-run` to preview changes before writing; use `--force` to
  skip the overwrite prompt.

## What doesn't have the marker

**Migrations.** Every `mix caravela.gen.schema` (and the all-in-one
`mix caravela.gen`) emits a *new* migration file with a fresh
timestamp. It contains the full desired schema — not a diff.

The deliberate design: Caravela is **stateless about schema
evolution**. It produces the desired state; you (or your LLM) write
the bridging `ALTER TABLE` migration.

- First generation → use the emitted migration directly.
- Subsequent generations → ignore the new migration, write your own
  with `mix ecto.gen.migration`, or ask an LLM to diff the emitted
  file against your production schema.

**Router.** Caravela doesn't edit `router.ex`. It prints a `scope`
block for you to paste once, after which it's yours to evolve.

## Why no auto-differ

Tools like Ash include a custom migration diff engine. That's a lot
of complexity and bug surface area for what Ecto already does well
with `mix ecto.gen.migration`. Caravela's approach — regenerate the
desired schema, bridge by hand — keeps the library small and
debuggable.

## Primary keys and ids

Every generated schema uses `:binary_id` (UUID) primary and foreign
keys. No enumeration attacks, no sequence exhaustion, Ecto-native, and
safe to expose in URLs.

## File-by-file marker behavior

| File type              | Marker format                    | What's above         | What's below |
|------------------------|----------------------------------|----------------------|--------------|
| Ecto schema            | `# --- CUSTOM ---`               | module + changeset   | preserved    |
| Phoenix context        | `# --- CUSTOM ---`               | CRUD + auth + hooks  | preserved    |
| JSON controller        | `# --- CUSTOM ---`               | REST actions + helpers | preserved  |
| Absinthe types/queries/mutations | `# --- CUSTOM ---`     | schema notation      | preserved    |
| LiveView module        | `# --- CUSTOM ---`               | mount + handle_event + render | preserved |
| Live.Domain module     | `# --- CUSTOM ---`               | state + updaters     | preserved    |
| Svelte component       | `<!-- --- CUSTOM --- -->`        | `<script>` + markup  | preserved    |
| TypeScript interfaces  | `// --- CUSTOM ---`              | `export interface`   | preserved    |
| Migration              | *(no marker — fresh each run)*   | —                    | —            |
