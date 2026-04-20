# Testing Caravela

Two stories on one page:

1. **Testing apps Caravela generates for you** - the ExUnit + Vitest
   skeletons `mix caravela.gen.live` emits, and how to fill them in.
   Jump to [Generated test skeletons](#generated-test-skeletons).
2. **Testing Caravela itself** - the three-tier approach used inside
   this repo to verify the code generators emit the right shape.
   Jump to [Tier 1: structural assertions](#tier-1-structural-assertions).

Most users only need 1. 2 is for contributors.

## Generated test skeletons

From v0.13, `mix caravela.gen.live MyApp.Domains.Library` emits a
CI-ready test layer alongside the implementation:

```
test/my_app_web/live/library/book_live_test.exs          # :live entities
test/my_app_web/controllers/book_controller_test.exs     # :rest entities
assets/svelte/library/BookIndex.test.ts                  # Vitest per component
assets/svelte/library/BookShow.test.ts
assets/svelte/library/BookForm.test.ts
```

### ExUnit skeletons

Each test file covers one entity. LiveView tests group `describe`
blocks per module (Index / Show / Form); controller tests group one
per HTTP action. Every test carries a single assertion + a `# TODO:`
marker where the app-specific fixture plugs in:

```elixir
defp build_book_fixture(attrs \\ %{}) do
  {:ok, entity} = attrs |> Enum.into(%{}) |> Library.create_book(build_context())
  entity
end

defp build_context, do: %{current_user: nil}

describe "index" do
  test "lists books", %{conn: conn} do
    _entity = build_book_fixture()
    {:ok, _view, html} = live(conn, "/library/books")
    # TODO: assert the fixture is visible in the rendered list.
    assert is_binary(html)
  end

  # …
end
```

The skeletons use the standard Phoenix test stack
(`Phoenix.ConnTest`, `Phoenix.LiveViewTest`) and assume the app has
`*.ConnCase` under `test/support/conn_case.ex` - which `mix phx.new`
emits by default. Pre-wired:

- Structured-error assertions reference
  [`Caravela.ChangesetTranslator`](validation.md) so the frontend
  contract stays aligned.
- `# TODO:` comments call out exactly where to replace the fixture
  factory with your app's ExMachina / factory module / Repo insert.
- Generated code sits above the `# --- CUSTOM ---` marker; anything
  you add below survives regeneration ([regeneration](regeneration.md)).

### Vitest skeletons

Colocated next to each Svelte file, using
`@testing-library/svelte`:

```ts
import { render } from '@testing-library/svelte';
import BookIndex from './BookIndex.svelte';

describe('BookIndex', () => {
  test('mounts with an empty collection', () => {
    const { container } = render(BookIndex, {
      props: {
        books: [],
        loading: false,
        flash_message: null,
        field_access: { title: true, isbn: true, /* … */ },
        actions: { create: true, update: true, delete: true }
      }
    });
    expect(container).toBeTruthy();
  });
});
```

These are intentionally thin - a CI oracle that catches "my prop
contract changed and the component now throws", not a full UX
regression suite. Install the dev deps in your app's
`assets/package.json`:

```json
{
  "devDependencies": {
    "@testing-library/svelte": "^5",
    "vitest": "^1"
  }
}
```

Run with `npm test` (after wiring `vitest` into your package
scripts).

### Opting out

```bash
mix caravela.gen.live --no-tests MyApp.Domains.Library
```

Skips emission of every test file. The implementation files still
generate normally.

---

# Testing Caravela itself

Caravela's own test suite sits in a corner that most libraries avoid:
we test a code generator. Every assertion has to decide whether it's
checking *the shape* of the generated source or *the behavior* the
source produces. String matching on generated code makes the suite
fragile - a formatter tweak cascades into dozens of test edits - so we
use the three-tier approach below.

## Tier 1: structural assertions

Use these when you want to check "did the template emit a call /
definition / attribute?" without caring about surrounding cosmetics.

### Generated Elixir → `Caravela.ASTAssertions`

Parses the source and walks the AST looking for the specific node
you care about.

```elixir
import Caravela.ASTAssertions

test "list_books pipes through apply_scope + project_fields" do
  {_path, src} = Caravela.Gen.Context.render(domain)

  # Matches regardless of line wrap, argument formatting, or
  # surrounding pipeline shape.
  assert_calls src, :apply_scope,    [:books, :_]
  assert_calls src, :project_fields, [:books, :_]
  assert_def   src, :list_books,     1
end
```

Argument matchers: `:_` wildcards anything, atoms / strings / other
terms compare with `==`.

Match qualified remote calls with `module:`:

```elixir
assert_calls src, :__caravela_policy_field_visible__, [:books, :price, :_],
  module: PolicyLibrary
```

The `module` comparison checks the *last segment* of the alias by
default, so `MyApp.Domains.PolicyLibrary.foo(…)` matches
`module: PolicyLibrary`.

### Generated Svelte / TypeScript → `Caravela.SvelteAssertions`

TS/Svelte AST parsing from Elixir is overkill for what we need.
Instead, normalize every whitespace run to a single space on both
sides before substring matching:

```elixir
import Caravela.SvelteAssertions

assert_contains  src, "let { books = [], live } = $props();"
refute_contains  src, "hashed_password"
assert_all_contain src, [
  "import type { Book, BookFieldAccess, LiveHandle }",
  "field_access?: BookFieldAccess;"
]
```

Line breaks and indentation differences are invisible to these
assertions, but the fragment still has to appear *in order*.

## Tier 2: compile + exercise

Sometimes the test isn't "did the template emit X?" - it's "does the
code actually work?". For those, compile the generated source into an
isolated namespace and call into it. [context_integration_test.exs](../test/caravela/context_integration_test.exs)
is the worked example: it renders the context, rewrites the module
aliases into a unique suffix, compiles via `Code.compile_string/1`,
then exercises CRUD round-trips against an in-memory stub Repo.

Use this tier when:

- You're verifying *behavior* across multiple generated files (context
  calling into schema calling into Repo stub).
- The rule under test has branches that AST matching alone can't
  distinguish ("does this policy deny when the actor lacks the role,
  *and* return the right error shape?").

## Tier 3: end-to-end

Not routinely used. A future expansion would spin up an ephemeral
Phoenix app against a test database, run every generator, migrate,
and issue HTTP requests. The cost/benefit usually lands better at
Tier 2 - but this doc will update if the e2e harness lands.

## When to reach for `src =~ "literal"`

Only for tokens that are genuinely positional and stable - CUSTOM
markers, fixed doc strings, the `@generated` header. For anything
that could move under a formatter tweak, prefer Tier 1.
