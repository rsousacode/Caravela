defmodule Caravela.Flow.Supervisor do
  @moduledoc """
  DynamicSupervisor for flow runner processes.

  Host applications start this supervisor in their own tree (usually
  under the application supervisor):

      children = [
        # ... other children ...
        Caravela.Flow.Supervisor
      ]
      Supervisor.start_link(children, strategy: :one_for_one)

  Once running, `Caravela.Flow.start/3` starts runners as supervised
  children. If the supervisor is not running, `start/3` falls back to
  starting an unsupervised runner - handy for tests and tooling.
  """

  use DynamicSupervisor

  def start_link(init_arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc false
  def start_runner(args) do
    DynamicSupervisor.start_child(__MODULE__, {Caravela.Flow.Runner, args})
  end
end
