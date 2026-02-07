defmodule ADK.Flow.Processors.Contents do
  @moduledoc """
  Builds conversation history from session events and appends to the request.

  Filters events by branch. Converts foreign agent events to user-perspective
  text (so the LLM sees a coherent conversation from its own perspective).
  """

  alias ADK.Agent.InvocationContext
  alias ADK.Model.LlmRequest
  alias ADK.Types
  alias ADK.Types.Content

  @spec process(InvocationContext.t(), LlmRequest.t(), map()) :: {:ok, LlmRequest.t()}
  def process(%InvocationContext{} = ctx, %LlmRequest{} = request, _flow_state) do
    agent = ctx.agent
    agent_name = if agent, do: agent.__struct__.name(agent), else: nil

    include_contents = Map.get(agent, :include_contents, :default)

    contents =
      if include_contents == :none do
        []
      else
        build_contents(ctx.session, ctx.branch, agent_name)
      end

    {:ok, %{request | contents: request.contents ++ contents}}
  end

  defp build_contents(nil, _branch, _agent_name), do: []

  defp build_contents(session, branch, agent_name) do
    session.events
    |> Enum.filter(&event_matches_branch?(&1, branch))
    |> Enum.reject(fn e -> e.partial end)
    |> Enum.filter(fn e -> e.content != nil end)
    |> Enum.map(fn event -> normalize_content(event, agent_name) end)
    |> merge_consecutive_roles()
  end

  defp event_matches_branch?(event, nil), do: event.branch == nil
  defp event_matches_branch?(event, branch), do: event.branch == branch or event.branch == nil

  defp normalize_content(event, agent_name) do
    content = event.content

    cond do
      event.author == agent_name ->
        # This agent's own output → model role
        %{content | role: Types.role_model()}

      content.role == Types.role_model() and event.author != agent_name ->
        # Another agent's model output → convert to user perspective
        convert_foreign_model_content(event)

      true ->
        content
    end
  end

  defp convert_foreign_model_content(event) do
    content = event.content

    if Types.has_function_calls?(content) or Types.has_function_responses?(content) do
      nil
    else
      build_foreign_text_content(event)
    end
  end

  defp build_foreign_text_content(event) do
    text =
      event.content.parts
      |> Enum.map_join("", fn part -> if part.text, do: part.text, else: "" end)

    if text == "" do
      nil
    else
      prefix = if event.author, do: "[#{event.author}] ", else: ""
      Content.new_from_text(Types.role_user(), prefix <> text)
    end
  end

  defp merge_consecutive_roles(contents) do
    contents
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_while(
      nil,
      fn content, acc ->
        cond do
          acc == nil ->
            {:cont, content}

          acc.role == content.role ->
            {:cont, %{acc | parts: acc.parts ++ content.parts}}

          true ->
            {:cont, acc, content}
        end
      end,
      fn
        nil -> {:cont, []}
        acc -> {:cont, acc, nil}
      end
    )
  end
end
