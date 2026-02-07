defmodule ADK.Agent.LoopAgent do
  @moduledoc """
  An agent that runs its sub-agents iteratively in sequence.

  Each iteration runs all sub-agents in order. The loop continues until:
  - `max_iterations` is reached (if > 0)
  - A sub-agent sets `escalate: true` in its event actions
  - A sub-agent sets `transfer_to_agent` in its event actions

  State changes from each sub-agent's events are propagated to subsequent
  sub-agents within the same iteration and across iterations.

  `SequentialAgent` is implemented as a `LoopAgent` with `max_iterations: 1`.
  """

  @behaviour ADK.Agent

  alias ADK.Agent.InvocationContext

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          sub_agents: [struct()],
          max_iterations: non_neg_integer()
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    description: "",
    sub_agents: [],
    max_iterations: 0
  ]

  @impl ADK.Agent
  def name(%__MODULE__{name: name}), do: name

  @impl ADK.Agent
  def description(%__MODULE__{description: desc}), do: desc

  @impl ADK.Agent
  def sub_agents(%__MODULE__{sub_agents: agents}), do: agents

  @impl ADK.Agent
  def run(%__MODULE__{} = agent, %InvocationContext{} = ctx) do
    Stream.resource(
      fn -> {:loop, agent, ctx, remaining(agent)} end,
      &next/1,
      fn _ -> :ok end
    )
  end

  defp remaining(%__MODULE__{max_iterations: 0}), do: :infinite
  defp remaining(%__MODULE__{max_iterations: n}), do: n

  defp next(:done), do: {:halt, :done}

  defp next({:loop, agent, ctx, remaining}) do
    {events, should_exit, updated_ctx} = run_one_iteration(agent, ctx)

    cond do
      should_exit ->
        {events, :done}

      remaining != :infinite and remaining <= 1 ->
        {events, :done}

      true ->
        next_remaining = if remaining == :infinite, do: :infinite, else: remaining - 1
        {events, {:loop, agent, updated_ctx, next_remaining}}
    end
  end

  defp run_one_iteration(agent, ctx) do
    Enum.reduce_while(agent.sub_agents, {[], false, ctx}, fn sub_agent, {acc_events, _exit, acc_ctx} ->
      sub_ctx = InvocationContext.with_agent(acc_ctx, sub_agent)
      sub_events = sub_agent.__struct__.run(sub_agent, sub_ctx) |> Enum.to_list()
      updated_ctx = apply_state_deltas(acc_ctx, sub_events)
      all_events = acc_events ++ sub_events
      should_exit = any_escalate_or_transfer?(sub_events)

      if should_exit do
        {:halt, {all_events, true, updated_ctx}}
      else
        {:cont, {all_events, false, updated_ctx}}
      end
    end)
  end

  defp apply_state_deltas(ctx, events) do
    Enum.reduce(events, ctx, fn event, acc ->
      if acc.session && map_size(event.actions.state_delta) > 0 do
        updated_state = Map.merge(acc.session.state, event.actions.state_delta)
        updated_session = %{acc.session | state: updated_state}
        %{acc | session: updated_session}
      else
        acc
      end
    end)
  end

  defp any_escalate_or_transfer?(events) do
    Enum.any?(events, fn event ->
      event.actions.escalate == true or event.actions.transfer_to_agent != nil
    end)
  end
end
