defmodule ADK.Tool.TransferToAgent do
  @moduledoc """
  A tool that signals a transfer to another agent.

  When an LLM calls this tool, the result contains a `"transfer_to_agent"` key
  that the Flow detects and uses to delegate execution to the target agent.

  This tool is automatically injected by the `AgentTransfer` request processor
  when the current agent has transfer targets (sub-agents, parent, or peers).
  """

  @behaviour ADK.Tool

  alias ADK.Tool.Context

  @type t :: %__MODULE__{}

  defstruct []

  @impl ADK.Tool
  def name(%__MODULE__{}), do: "transfer_to_agent"

  @impl ADK.Tool
  def description(%__MODULE__{}),
    do: "Transfer the conversation to another agent. Use this when the user's request is better handled by a different agent."

  @impl ADK.Tool
  def declaration(%__MODULE__{}) do
    %{
      "name" => "transfer_to_agent",
      "description" =>
        "Transfer the conversation to another agent. Use this when the user's request is better handled by a different agent.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "agent_name" => %{
            "type" => "string",
            "description" => "The name of the agent to transfer to."
          }
        },
        "required" => ["agent_name"]
      }
    }
  end

  @impl ADK.Tool
  def run(%__MODULE__{}, %Context{}, args) do
    agent_name = Map.get(args, "agent_name")

    if is_binary(agent_name) and agent_name != "" do
      {:ok, %{"transfer_to_agent" => agent_name}}
    else
      {:error, "agent_name is required and must be a non-empty string"}
    end
  end
end
