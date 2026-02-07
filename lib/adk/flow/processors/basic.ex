defmodule ADK.Flow.Processors.Basic do
  @moduledoc """
  Copies the agent's generate_content_config into the LLM request config.
  """

  alias ADK.Agent.InvocationContext
  alias ADK.Model.LlmRequest

  @spec process(InvocationContext.t(), LlmRequest.t(), map()) :: {:ok, LlmRequest.t()}
  def process(%InvocationContext{agent: agent}, %LlmRequest{} = request, _flow_state) do
    config =
      if agent && is_map(agent_config(agent)) do
        Map.merge(request.config, agent_config(agent))
      else
        request.config
      end

    {:ok, %{request | config: config}}
  end

  defp agent_config(agent) do
    Map.get(agent, :generate_content_config, %{})
  end
end
