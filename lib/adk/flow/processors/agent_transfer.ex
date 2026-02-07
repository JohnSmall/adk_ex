defmodule ADK.Flow.Processors.AgentTransfer do
  @moduledoc """
  Request processor that injects the `transfer_to_agent` tool and transfer
  instructions into the LLM request when the current agent has transfer targets.

  Transfer targets include:
  - Sub-agents of the current agent
  - Parent agent (unless `disallow_transfer_to_parent` is set)
  - Peer agents (unless `disallow_transfer_to_peers` is set)
  """

  alias ADK.Agent.InvocationContext
  alias ADK.Agent.LlmAgent
  alias ADK.Model.LlmRequest
  alias ADK.Tool
  alias ADK.Tool.TransferToAgent

  @spec process(InvocationContext.t(), LlmRequest.t(), map()) :: {:ok, LlmRequest.t()}
  def process(%InvocationContext{} = ctx, %LlmRequest{} = request, _flow_state) do
    agent = ctx.agent

    if should_inject?(agent) do
      targets = build_targets(agent, ctx)

      if targets == [] do
        {:ok, request}
      else
        inject_transfer(request, targets)
      end
    else
      {:ok, request}
    end
  end

  defp should_inject?(%LlmAgent{} = agent) do
    agent.sub_agents != [] or not agent.disallow_transfer_to_parent or
      not agent.disallow_transfer_to_peers
  end

  defp should_inject?(_), do: false

  defp build_targets(agent, ctx) do
    targets = []
    targets = targets ++ sub_agent_targets(agent)
    targets = targets ++ parent_targets(agent, ctx)
    targets = targets ++ peer_targets(agent, ctx)
    targets
  end

  defp sub_agent_targets(agent) do
    Enum.map(agent.sub_agents, fn sub ->
      {sub.__struct__.name(sub), sub.__struct__.description(sub)}
    end)
  end

  defp parent_targets(agent, ctx) do
    if agent.disallow_transfer_to_parent do
      []
    else
      case Map.get(ctx.parent_map, agent.name) do
        nil -> []
        parent -> [{parent.__struct__.name(parent), parent.__struct__.description(parent)}]
      end
    end
  end

  defp peer_targets(agent, ctx) do
    if agent.disallow_transfer_to_peers do
      []
    else
      agent.name |> find_peers(ctx.parent_map) |> to_name_desc_pairs()
    end
  end

  defp find_peers(agent_name, parent_map) do
    case Map.get(parent_map, agent_name) do
      nil ->
        []

      parent ->
        parent
        |> get_sub_agents()
        |> Enum.reject(fn peer -> peer.__struct__.name(peer) == agent_name end)
    end
  end

  defp to_name_desc_pairs(agents) do
    Enum.map(agents, fn a -> {a.__struct__.name(a), a.__struct__.description(a)} end)
  end

  defp get_sub_agents(agent) do
    if function_exported?(agent.__struct__, :sub_agents, 1) do
      agent.__struct__.sub_agents(agent)
    else
      []
    end
  end

  defp inject_transfer(request, targets) do
    transfer_tool = %TransferToAgent{}

    # Add tool to the tools map
    tools_map = Map.put(request.tools, Tool.name(transfer_tool), transfer_tool)

    # Add declaration to config
    existing_tools = get_in(request.config, ["tools"]) || []

    existing_declarations =
      case existing_tools do
        [%{"function_declarations" => decls} | _] -> decls
        _ -> []
      end

    all_declarations = existing_declarations ++ [Tool.declaration(transfer_tool)]
    config = Map.put(request.config, "tools", [%{"function_declarations" => all_declarations}])

    # Append transfer instructions to system instruction
    transfer_text = build_transfer_instruction(targets)
    updated_system = append_to_system(request.system_instruction, transfer_text)

    {:ok, %{request | tools: tools_map, config: config, system_instruction: updated_system}}
  end

  defp build_transfer_instruction(targets) do
    agent_list =
      Enum.map_join(targets, "\n", fn {name, desc} ->
        if desc == "", do: "- #{name}", else: "- #{name}: #{desc}"
      end)

    "\n\nYou can transfer the conversation to the following agents using the transfer_to_agent tool:\n#{agent_list}"
  end

  defp append_to_system(nil, text) do
    ADK.Types.Content.new_from_text("user", text)
  end

  defp append_to_system(%ADK.Types.Content{parts: parts} = content, text) do
    existing_text =
      parts
      |> Enum.map_join("", fn part -> if part.text, do: part.text, else: "" end)

    ADK.Types.Content.new_from_text(content.role, existing_text <> text)
  end
end
