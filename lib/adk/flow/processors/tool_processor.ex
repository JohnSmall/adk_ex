defmodule ADK.Flow.Processors.ToolProcessor do
  @moduledoc """
  Populates the request's tools map and adds function declarations to config.
  """

  alias ADK.Agent.InvocationContext
  alias ADK.Model.LlmRequest
  alias ADK.Tool

  @spec process(InvocationContext.t(), LlmRequest.t(), map()) :: {:ok, LlmRequest.t()}
  def process(%InvocationContext{} = _ctx, %LlmRequest{} = request, flow_state) do
    tools = Map.get(flow_state, :tools, [])

    if tools == [] do
      {:ok, request}
    else
      tools_map =
        Map.new(tools, fn tool -> {Tool.name(tool), tool} end)

      declarations =
        Enum.map(tools, fn tool -> Tool.declaration(tool) end)

      config =
        Map.put(request.config, "tools", [
          %{"function_declarations" => declarations}
        ])

      {:ok, %{request | tools: tools_map, config: config}}
    end
  end
end
