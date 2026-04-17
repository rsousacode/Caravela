defmodule Caravela.Flow.Steps do
  @moduledoc """
  Step primitives that make up a flow tree.

  A compiled flow is a nested tree of these structs (typically rooted
  at `Sequence` or `Repeat`). `Caravela.Flow.Runner` walks the tree,
  one step at a time, updating the flow state and notifying listeners
  as it goes.

  ### Semantic overview (Ballerina mapping in parens)

    * `Sequence` (`Co.Seq`) — run inner steps in order
    * `Repeat`   (`Co.Repeat`) — loop the inner step forever
    * `Wait`     (`Co.Wait`) — pause for a fixed duration
    * `WaitUntil` (`Co.While`) — block until a predicate over state
      becomes true
    * `Debounce` — pause, but reset the timer if state changes during
      the pause
    * `SetState` (`Co.SetState`) — mutate state synchronously
    * `Run`      (`Co.Await`) — invoke async work with optional retry
      + backoff
    * `Parallel` (`Co.All`) — run a list of tasks concurrently, collect
      all results into a state key
    * `Race`     (`Co.Any`) — run tasks concurrently, keep the first
      result
    * `Each`     (`Co.For`) — iterate a collection already in state

  Each struct holds only data (funs + configs). Interpretation lives
  in `Caravela.Flow.Runner`.
  """

  defmodule Sequence do
    @moduledoc "Run `steps` in order."
    defstruct steps: []

    @type t :: %__MODULE__{steps: [any()]}
  end

  defmodule Repeat do
    @moduledoc "Loop `step` forever. Break by raising or via `{:error, _}` from Run."
    defstruct [:step]

    @type t :: %__MODULE__{step: any()}
  end

  defmodule Wait do
    @moduledoc "Pause for `ms` milliseconds, then advance."
    defstruct ms: 0

    @type t :: %__MODULE__{ms: non_neg_integer()}
  end

  defmodule WaitUntil do
    @moduledoc "Block until `fun.(state)` returns truthy, then advance."
    defstruct [:fun]

    @type t :: %__MODULE__{fun: (map() -> boolean())}
  end

  defmodule Debounce do
    @moduledoc """
    Wait for `ms` of state-stability, then advance.

    Concretely: schedule an advance after `ms`. If state changes during
    the pause (via `SetState`, `Run`, or an external `signal/2`), the
    timer resets.
    """
    defstruct ms: 0

    @type t :: %__MODULE__{ms: non_neg_integer()}
  end

  defmodule SetState do
    @moduledoc "Synchronously apply `fun.(state)` → new state."
    defstruct [:fun]

    @type t :: %__MODULE__{fun: (map() -> map())}
  end

  defmodule Run do
    @moduledoc """
    Run `fun.(state)` once. The return value drives what happens next:

      * `:ok` — advance, state unchanged
      * `{:ok, new_state}` — advance with new state
      * `{:retry, new_state}` — retry (if `retries > 0`) with new state
      * `{:error, reason}` — retry (if `retries > 0`) else fail flow
    """
    defstruct [:fun, retries: 0, backoff: :linear, base_delay: 100]

    @type backoff :: :linear | :exponential

    @type t :: %__MODULE__{
            fun: (map() -> any()),
            retries: non_neg_integer(),
            backoff: backoff(),
            base_delay: non_neg_integer()
          }
  end

  defmodule Parallel do
    @moduledoc """
    Invoke `tasks_fn.(state)` to build a list of zero-arity funs, run
    them all concurrently, and collect each one's return under the
    `collect_as` key in state.
    """
    defstruct [:tasks_fn, collect_as: :parallel_results, timeout: 5_000]

    @type t :: %__MODULE__{
            tasks_fn: (map() -> [(-> any())]),
            collect_as: atom(),
            timeout: non_neg_integer()
          }
  end

  defmodule Race do
    @moduledoc """
    Run every fun in `tasks` concurrently, take the first to return.
    The winner is stored under the `collect_as` key.
    """
    defstruct tasks: [], collect_as: :race_winner, timeout: 5_000

    @type t :: %__MODULE__{
            tasks: [(-> any())],
            collect_as: atom(),
            timeout: non_neg_integer()
          }
  end

  defmodule Each do
    @moduledoc """
    Iterate a collection already in state under `key`. For every item,
    invoke `fun.(item, state)`. The fun may return:

      * `{:ok, new_state}` — continue with updated state
      * `{:skip, reason}`  — skip this item, continue
      * `{:error, reason}` — abort the whole flow
    """
    defstruct [:key, :fun]

    @type t :: %__MODULE__{key: atom(), fun: (any(), map() -> any())}
  end
end
