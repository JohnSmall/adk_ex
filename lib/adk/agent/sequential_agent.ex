defmodule ADK.Agent.SequentialAgent do
  @moduledoc """
  An agent that runs its sub-agents once in sequence.

  Implemented as a `LoopAgent` with `max_iterations: 1`, matching the
  Go ADK pattern where SequentialAgent delegates to LoopAgent.

  State changes propagate from one sub-agent to the next. If any sub-agent
  sets `escalate: true` or `transfer_to_agent`, subsequent sub-agents are skipped.
  """

  @behaviour ADK.Agent

  alias ADK.Agent.{InvocationContext, LoopAgent}

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          sub_agents: [struct()]
        }

  @enforce_keys [:name]
  defstruct [:name, description: "", sub_agents: []]

  @impl ADK.Agent
  def name(%__MODULE__{name: name}), do: name

  @impl ADK.Agent
  def description(%__MODULE__{description: desc}), do: desc

  @impl ADK.Agent
  def sub_agents(%__MODULE__{sub_agents: agents}), do: agents

  @impl ADK.Agent
  def run(%__MODULE__{} = agent, %InvocationContext{} = ctx) do
    loop = %LoopAgent{
      name: agent.name,
      description: agent.description,
      sub_agents: agent.sub_agents,
      max_iterations: 1
    }

    LoopAgent.run(loop, ctx)
  end
end
