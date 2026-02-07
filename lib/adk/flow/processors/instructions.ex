defmodule ADK.Flow.Processors.Instructions do
  @moduledoc """
  Injects system instructions into the LLM request.

  Combines global instruction and agent instruction. Supports `{variable}`
  interpolation from session state. Variables suffixed with `?` (e.g. `{name?}`)
  are optional and silently removed if not found.
  """

  alias ADK.Agent.InvocationContext
  alias ADK.Model.LlmRequest
  alias ADK.Types.Content

  @spec process(InvocationContext.t(), LlmRequest.t(), map()) :: {:ok, LlmRequest.t()}
  def process(%InvocationContext{} = ctx, %LlmRequest{} = request, _flow_state) do
    agent = ctx.agent
    parts = []

    parts = maybe_add_instruction(parts, get_global_instruction(agent, ctx))
    parts = maybe_add_instruction(parts, get_instruction(agent, ctx))

    if parts == [] do
      {:ok, request}
    else
      text = Enum.join(parts, "\n")
      interpolated = interpolate(text, session_state(ctx))
      system = Content.new_from_text("user", interpolated)
      {:ok, %{request | system_instruction: system}}
    end
  end

  defp get_global_instruction(agent, ctx) do
    cond do
      is_function(Map.get(agent, :global_instruction_provider)) ->
        agent.global_instruction_provider.(ctx)

      is_binary(Map.get(agent, :global_instruction, "")) and
          Map.get(agent, :global_instruction, "") != "" ->
        agent.global_instruction

      true ->
        nil
    end
  end

  defp get_instruction(agent, ctx) do
    cond do
      is_function(Map.get(agent, :instruction_provider)) ->
        agent.instruction_provider.(ctx)

      is_binary(Map.get(agent, :instruction, "")) and Map.get(agent, :instruction, "") != "" ->
        agent.instruction

      true ->
        nil
    end
  end

  defp maybe_add_instruction(parts, nil), do: parts
  defp maybe_add_instruction(parts, ""), do: parts
  defp maybe_add_instruction(parts, text), do: parts ++ [text]

  defp session_state(%InvocationContext{session: nil}), do: %{}
  defp session_state(%InvocationContext{session: session}), do: session.state

  @doc false
  @spec interpolate(String.t(), map()) :: String.t()
  def interpolate(text, state) do
    Regex.replace(~r/\{(\w+\??)\}/, text, fn _match, var_name ->
      {key, optional?} =
        if String.ends_with?(var_name, "?") do
          {String.trim_trailing(var_name, "?"), true}
        else
          {var_name, false}
        end

      case Map.fetch(state, key) do
        {:ok, value} -> to_string(value)
        :error when optional? -> ""
        :error -> "{#{var_name}}"
      end
    end)
  end
end
