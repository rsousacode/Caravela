defmodule Caravela.Flow.DSL do
  @moduledoc """
  DSL macros for declaring flows. Pulled in via `use Caravela.Flow`.

      defmodule MyApp.Flows.BookSyncFlow do
        use Caravela.Flow

        flow :sync_book, initial_state: %{dirty: false, book_id: nil} do
          repeat do
            wait_until fn state -> state.dirty end
            debounce 500

            sequence do
              set_state fn state -> %{state | dirty: :processing} end

              run fn state ->
                case MyApp.ExternalAPI.sync_book(state.book_id) do
                  :ok -> {:ok, %{state | dirty: false}}
                  {:error, :timeout} -> {:retry, state}
                  {:error, reason} -> {:error, reason}
                end
              end,
              retries: 3, backoff: :exponential, base_delay: 200
            end
          end
        end
      end

  Every `flow/3` declaration compiles into two lookup functions:

    * `__caravela_flow__/1` - returns the compiled step tree for the
      given flow name.
    * `__caravela_flow_initial_state__/1` - returns the default
      initial-state map.

  `__caravela_flows__/0` lists every declared name.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Caravela.Flow.DSL

      Module.register_attribute(__MODULE__, :caravela_flows, accumulate: true)
      @before_compile Caravela.Flow.DSL
    end
  end

  @doc """
  Declare a flow.

      flow :name, initial_state: %{...} do
        ...
      end

  The block is compiled into a step tree consumed by
  `Caravela.Flow.Runner`.
  """
  defmacro flow(name, opts \\ [], do: block) do
    unless is_atom(name) do
      raise Caravela.DSLError,
        message: "flow name must be an atom, got: #{inspect(name)}",
        suggestion: "flow :sync_book, initial_state: %{...} do\n  ...\nend",
        docs_url: "https://hexdocs.pm/caravela/flows.html"
    end

    initial_state =
      case Keyword.fetch(opts, :initial_state) do
        {:ok, ast} -> ast
        :error -> Macro.escape(%{})
      end

    tree = block_to_sequence(block)

    quote do
      @caravela_flows unquote(name)

      @doc false
      def __caravela_flow__(unquote(name)), do: unquote(tree)

      @doc false
      def __caravela_flow_initial_state__(unquote(name)), do: unquote(initial_state)
    end
  end

  @doc "Sequence block. Runs inner steps in order."
  defmacro sequence(do: block), do: block_to_sequence(block)

  @doc "Repeat block. Runs the inner block forever."
  defmacro repeat(do: block) do
    inner = block_to_sequence(block)

    quote do
      %Caravela.Flow.Steps.Repeat{step: unquote(inner)}
    end
  end

  @doc "Pause for `ms` milliseconds."
  defmacro wait(ms) do
    quote do
      %Caravela.Flow.Steps.Wait{ms: unquote(ms)}
    end
  end

  @doc "Block until `fun.(state)` returns truthy."
  defmacro wait_until(fun) do
    quote do
      %Caravela.Flow.Steps.WaitUntil{fun: unquote(fun)}
    end
  end

  @doc "Pause until state has been stable for `ms` milliseconds."
  defmacro debounce(ms) do
    quote do
      %Caravela.Flow.Steps.Debounce{ms: unquote(ms)}
    end
  end

  @doc "Synchronously replace state via `fun.(state)`."
  defmacro set_state(fun) do
    quote do
      %Caravela.Flow.Steps.SetState{fun: unquote(fun)}
    end
  end

  @doc """
  Run `fun.(state)` once, with optional retry/backoff.

      run fn state -> ... end, retries: 3, backoff: :exponential, base_delay: 200

  Accepted options:

    * `:retries`    - how many retries on `{:error, _}` / `{:retry, _}`
    * `:backoff`    - `:linear` (default) or `:exponential`
    * `:base_delay` - ms multiplier for retry delay (default `100`)
  """
  defmacro run(fun, opts \\ []) do
    retries = Keyword.get(opts, :retries, 0)
    backoff = Keyword.get(opts, :backoff, :linear)
    base_delay = Keyword.get(opts, :base_delay, 100)

    quote do
      %Caravela.Flow.Steps.Run{
        fun: unquote(fun),
        retries: unquote(retries),
        backoff: unquote(backoff),
        base_delay: unquote(base_delay)
      }
    end
  end

  @doc """
  Run a dynamic list of zero-arity funs concurrently. Collect every
  return value under the `collect_as` state key.

      parallel fn state -> Enum.map(state.urls, &fetch_fn/1) end, collect_as: :fetched
  """
  defmacro parallel(fun, opts \\ []) do
    collect_as = Keyword.get(opts, :collect_as, :parallel_results)
    timeout = Keyword.get(opts, :timeout, 5_000)

    quote do
      %Caravela.Flow.Steps.Parallel{
        tasks_fn: unquote(fun),
        collect_as: unquote(collect_as),
        timeout: unquote(timeout)
      }
    end
  end

  @doc """
  Run zero-arity funs concurrently, keep the first to return.

      race [fn -> api_a() end, fn -> api_b() end], collect_as: :winner
  """
  defmacro race(tasks, opts \\ []) do
    collect_as = Keyword.get(opts, :collect_as, :race_winner)
    timeout = Keyword.get(opts, :timeout, 5_000)

    quote do
      %Caravela.Flow.Steps.Race{
        tasks: unquote(tasks),
        collect_as: unquote(collect_as),
        timeout: unquote(timeout)
      }
    end
  end

  @doc """
  Iterate the collection at `state[key]`. For each item, call
  `fun.(item, state)`; returning `{:ok, new_state}` threads the result
  to the next iteration.
  """
  defmacro each(key, fun) do
    quote do
      %Caravela.Flow.Steps.Each{key: unquote(key), fun: unquote(fun)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    flows = env.module |> Module.get_attribute(:caravela_flows) |> Enum.reverse()

    quote do
      @doc false
      def __caravela_flows__, do: unquote(flows)

      # Fallbacks - appear after the specific clauses injected by
      # every `flow/3` call.
      def __caravela_flow__(_name), do: nil
      def __caravela_flow_initial_state__(_name), do: %{}
    end
  end

  # --- Internal helpers -------------------------------------------------

  defp block_to_sequence({:__block__, _, statements}) do
    quote do
      %Caravela.Flow.Steps.Sequence{steps: [unquote_splicing(statements)]}
    end
  end

  defp block_to_sequence(single) do
    quote do
      %Caravela.Flow.Steps.Sequence{steps: [unquote(single)]}
    end
  end
end
