defmodule Caravela.Policy do
  @moduledoc """
  Intermediate Representation for Caravela's triple-target policy
  system.

  A `policy :entity do ... end` block in the domain DSL parses into a
  `Caravela.Policy.Entry` struct that captures three categories of
  rules:

    * `scope` — a 2-arity function `(query, actor) -> query` compiled
      into the context's `apply_scope/3` helper (Ecto WHERE clauses).
    * `field` rules — per-field visibility predicates of arity 1 or 2
      (`fn actor -> bool end` or `fn actor, record -> bool end`).
      Field rules compile into `compute_field_access/2` and
      `project_fields/3` on the context, and into the `field_access`
      prop reaching Svelte via LiveSvelte.
    * `allow` action gates — one per `{:create, :update, :delete}`.

  The `Caravela.Policy` module itself only holds the structs.
  `Caravela.Policy.Compiler` emits the matching `__caravela_policy_*__`
  function clauses into the domain module.
  """

  defmodule Scope do
    @moduledoc "A row-level scope rule for an entity."
    defstruct [:entity]

    @type t :: %__MODULE__{entity: atom()}
  end

  defmodule FieldRule do
    @moduledoc """
    A field-level visibility rule. `arity` is either 1 (depends only on
    the actor — static per request) or 2 (depends on actor + record —
    evaluated per-row).
    """
    defstruct [:entity, :field, :arity]

    @type t :: %__MODULE__{
            entity: atom(),
            field: atom(),
            arity: 1 | 2
          }
  end

  defmodule ActionGate do
    @moduledoc """
    A policy `allow :action, fn ... end` rule. `action` is one of
    `:create`, `:update`, `:delete`. `arity` is 1 or 2.
    """
    defstruct [:entity, :action, :arity]

    @type action :: :create | :update | :delete

    @type t :: %__MODULE__{
            entity: atom(),
            action: action(),
            arity: 1 | 2
          }
  end

  defmodule Entry do
    @moduledoc """
    The compiled IR for a single `policy :entity do ... end` block.

    The anonymous functions themselves live as clauses of
    `__caravela_policy_scope__/3`, `__caravela_policy_field_visible__/4`
    and `__caravela_policy_allow__/4` on the domain module. This struct
    is metadata so generators and the runtime helpers can reason about
    which rules exist per entity.
    """
    defstruct [:entity, :has_scope?, :fields, :actions]

    @type t :: %__MODULE__{
            entity: atom(),
            has_scope?: boolean(),
            fields: [FieldRule.t()],
            actions: [ActionGate.t()]
          }

    @doc "Does this entry have a field rule for `field`?"
    @spec field_rule(t(), atom()) :: FieldRule.t() | nil
    def field_rule(%__MODULE__{fields: fields}, field) do
      Enum.find(fields, &(&1.field == field))
    end

    @doc "Does this entry have an action gate for `action`?"
    @spec action_gate(t(), ActionGate.action()) :: ActionGate.t() | nil
    def action_gate(%__MODULE__{actions: gates}, action) do
      Enum.find(gates, &(&1.action == action))
    end
  end

  @action_gate_actions [:create, :update, :delete]

  @doc false
  @spec action_gate_actions() :: [ActionGate.action()]
  def action_gate_actions, do: @action_gate_actions
end
