defmodule ADK.Agent.ParallelAgent do
  @moduledoc """
  An agent that runs all its sub-agents concurrently.

  Each sub-agent runs in its own `Task` with an isolated branch. Events from
  all sub-agents are collected and returned in a single flat list.

  Branch naming follows the pattern `"parent.sub"` (or `"existing.parent.sub"`
  if the context already has a branch set).

  Since sub-agents run concurrently, the order of events across sub-agents
  is nondeterministic.
  """

  @behaviour ADK.Agent

  alias ADK.Agent.InvocationContext

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
    Stream.resource(
      fn -> {:run, agent, ctx} end,
      &next/1,
      fn _ -> :ok end
    )
  end

  defp next(:done), do: {:halt, :done}

  defp next({:run, agent, ctx}) do
    parent_name = agent.name

    tasks =
      Enum.map(agent.sub_agents, fn sub_agent ->
        sub_name = sub_agent.__struct__.name(sub_agent)
        branch = compute_branch(ctx.branch, parent_name, sub_name)
        sub_ctx = ctx |> InvocationContext.with_agent(sub_agent) |> InvocationContext.with_branch(branch)

        Task.async(fn ->
          sub_agent.__struct__.run(sub_agent, sub_ctx) |> Enum.to_list()
        end)
      end)

    results = Task.await_many(tasks, 30_000)
    events = List.flatten(results)
    {events, :done}
  end

  defp compute_branch(nil, parent, sub), do: "#{parent}.#{sub}"
  defp compute_branch(existing, parent, sub), do: "#{existing}.#{parent}.#{sub}"
end
