defmodule ADK.Flow do
  @moduledoc """
  Core execution engine for LLM agents.

  Implements the request→model→response→tool loop. Each iteration:
  1. Build an LlmRequest via request processors
  2. Run before_model callbacks (may short-circuit)
  3. Call the model's generate_content
  4. Run after_model callbacks
  5. If the response contains function calls, execute tools
  6. Yield events; loop if tool responses were generated
  """

  alias ADK.Agent.{CallbackContext, InvocationContext}
  alias ADK.Agent.Tree
  alias ADK.Event
  alias ADK.Event.Actions
  alias ADK.Model
  alias ADK.Model.{LlmRequest, LlmResponse}
  alias ADK.Tool
  alias ADK.Tool.Context, as: ToolContext
  alias ADK.Types
  alias ADK.Types.{Content, FunctionCall, FunctionResponse, Part}

  @type before_model_callback ::
          (CallbackContext.t(), LlmRequest.t() -> {LlmResponse.t() | nil, CallbackContext.t()})
  @type after_model_callback ::
          (CallbackContext.t(), LlmResponse.t() -> {LlmResponse.t() | nil, CallbackContext.t()})
  @type before_tool_callback ::
          (ToolContext.t(), struct(), map() -> {map() | nil, ToolContext.t()})
  @type after_tool_callback ::
          (ToolContext.t(), struct(), map(), map() -> {map() | nil, ToolContext.t()})

  @type request_processor ::
          (InvocationContext.t(), LlmRequest.t(), map() -> {:ok, LlmRequest.t()})

  @type t :: %__MODULE__{
          model: struct() | nil,
          tools: [struct()],
          request_processors: [request_processor()],
          response_processors: [term()],
          before_model_callbacks: [before_model_callback()],
          after_model_callbacks: [after_model_callback()],
          on_model_error_callbacks: [term()],
          before_tool_callbacks: [before_tool_callback()],
          after_tool_callbacks: [after_tool_callback()],
          on_tool_error_callbacks: [term()]
        }

  defstruct [
    :model,
    tools: [],
    request_processors: [],
    response_processors: [],
    before_model_callbacks: [],
    after_model_callbacks: [],
    on_model_error_callbacks: [],
    before_tool_callbacks: [],
    after_tool_callbacks: [],
    on_tool_error_callbacks: []
  ]

  @max_iterations 25

  @doc """
  Runs the flow loop, returning a stream of events.
  """
  @spec run(t(), InvocationContext.t()) :: Enumerable.t()
  def run(%__MODULE__{} = flow, %InvocationContext{} = ctx) do
    Stream.resource(
      fn -> {:step, flow, ctx, 0} end,
      &flow_next/1,
      fn _ -> :ok end
    )
  end

  defp flow_next(:done), do: {:halt, :done}

  defp flow_next({:step, _flow, ctx, iteration}) when iteration >= @max_iterations do
    event =
      Event.new(
        invocation_id: ctx.invocation_id,
        branch: ctx.branch,
        author: agent_name(ctx),
        error_code: "max_iterations",
        error_message: "Flow exceeded maximum iterations (#{@max_iterations})"
      )

    {[event], :done}
  end

  defp flow_next({:step, flow, ctx, iteration}) do
    case run_one_step(flow, ctx) do
      {:ok, events, updated_ctx} ->
        last = List.last(events)

        if last != nil and Event.final_response?(last) do
          {events, :done}
        else
          {events, {:step, flow, updated_ctx, iteration + 1}}
        end

      {:error, reason} ->
        event =
          Event.new(
            invocation_id: ctx.invocation_id,
            branch: ctx.branch,
            author: agent_name(ctx),
            error_code: "flow_error",
            error_message: to_string(reason)
          )

        {[event], :done}
    end
  end

  defp run_one_step(flow, ctx) do
    flow_state = %{tools: flow.tools}

    with {:ok, request} <- build_request(flow, ctx, flow_state),
         {:ok, response, cb_ctx} <- call_model_with_callbacks(flow, ctx, request),
         model_event <- build_model_event(ctx, response, cb_ctx) do
      function_calls = extract_function_calls(response)

      if function_calls == [] do
        {:ok, [model_event], update_ctx_from_event(ctx, model_event)}
      else
        {:ok, tool_event} = execute_tools(flow, ctx, request, function_calls)

        updated_ctx =
          ctx
          |> update_ctx_from_event(model_event)
          |> update_ctx_from_event(tool_event)

        transfer_events = maybe_run_transfer(tool_event, updated_ctx)
        {:ok, [model_event, tool_event] ++ transfer_events, updated_ctx}
      end
    end
  end

  defp build_request(flow, ctx, flow_state) do
    request = %LlmRequest{model: model_name(flow)}

    Enum.reduce_while(flow.request_processors, {:ok, request}, fn processor, {:ok, req} ->
      case processor.(ctx, req, flow_state) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp call_model_with_callbacks(flow, ctx, request) do
    cb_ctx = CallbackContext.new(ctx)

    case run_before_model_callbacks(flow.before_model_callbacks, cb_ctx, request) do
      {:short_circuit, response, updated_cb_ctx} ->
        {:ok, response, updated_cb_ctx}

      {:continue, updated_cb_ctx} ->
        stream? = ctx.run_config.streaming_mode != :none
        responses = flow.model |> Model.generate_content(request, stream?) |> Enum.to_list()
        final_response = find_final_response(responses)

        case run_after_model_callbacks(flow.after_model_callbacks, updated_cb_ctx, final_response) do
          {:replaced, replaced_response, after_cb_ctx} ->
            {:ok, replaced_response, after_cb_ctx}

          {:continue, after_cb_ctx} ->
            {:ok, final_response, after_cb_ctx}
        end
    end
  end

  defp run_before_model_callbacks([], cb_ctx, _request), do: {:continue, cb_ctx}

  defp run_before_model_callbacks([callback | rest], cb_ctx, request) do
    case callback.(cb_ctx, request) do
      {%LlmResponse{} = response, updated_ctx} -> {:short_circuit, response, updated_ctx}
      {nil, updated_ctx} -> run_before_model_callbacks(rest, updated_ctx, request)
    end
  end

  defp run_after_model_callbacks([], cb_ctx, _response), do: {:continue, cb_ctx}

  defp run_after_model_callbacks([callback | rest], cb_ctx, response) do
    case callback.(cb_ctx, response) do
      {%LlmResponse{} = replaced, updated_ctx} -> {:replaced, replaced, updated_ctx}
      {nil, updated_ctx} -> run_after_model_callbacks(rest, updated_ctx, response)
    end
  end

  defp find_final_response([]), do: %LlmResponse{turn_complete: true}

  defp find_final_response(responses) do
    Enum.reduce(responses, %LlmResponse{}, fn resp, acc ->
      merge_response(acc, resp)
    end)
  end

  defp merge_response(acc, new) do
    content = if new.content != nil, do: new.content, else: acc.content

    %LlmResponse{
      content: content,
      error_code: new.error_code || acc.error_code,
      error_message: new.error_message || acc.error_message,
      finish_reason: new.finish_reason || acc.finish_reason,
      usage_metadata: new.usage_metadata || acc.usage_metadata,
      turn_complete: new.turn_complete || acc.turn_complete,
      partial: false,
      interrupted: new.interrupted || acc.interrupted
    }
  end

  defp build_model_event(ctx, response, cb_ctx) do
    Event.new(
      invocation_id: ctx.invocation_id,
      branch: ctx.branch,
      author: agent_name(ctx),
      content: response.content,
      partial: response.partial,
      turn_complete: response.turn_complete,
      interrupted: response.interrupted,
      error_code: response.error_code,
      error_message: response.error_message,
      finish_reason: response.finish_reason,
      usage_metadata: response.usage_metadata,
      actions: cb_ctx.actions
    )
  end

  defp extract_function_calls(%LlmResponse{content: nil}), do: []

  defp extract_function_calls(%LlmResponse{content: content}) do
    Types.function_calls(content)
  end

  defp execute_tools(flow, ctx, request, function_calls) do
    cb_ctx = CallbackContext.new(ctx)

    results =
      Enum.map(function_calls, fn fc ->
        call_tool(flow, cb_ctx, request, fc)
      end)

    parts =
      Enum.map(results, fn {_tool_ctx, part} -> part end)

    merged_actions =
      Enum.reduce(results, %Actions{}, fn {tool_ctx, _part}, acc ->
        merge_actions(acc, tool_ctx.actions)
      end)

    event =
      Event.new(
        invocation_id: ctx.invocation_id,
        branch: ctx.branch,
        author: agent_name(ctx),
        content: %Content{role: Types.role_user(), parts: parts},
        actions: merged_actions
      )

    {:ok, event}
  end

  defp call_tool(flow, cb_ctx, request, %FunctionCall{} = fc) do
    tool_ctx = ToolContext.new(cb_ctx, fc.id)
    tool = Map.get(request.tools, fc.name)

    if tool == nil do
      error_part = %Part{
        function_response: %FunctionResponse{
          name: fc.name,
          id: fc.id,
          response: %{"error" => "Tool not found: #{fc.name}"}
        }
      }

      {tool_ctx, error_part}
    else
      do_call_tool(flow, tool_ctx, tool, fc)
    end
  end

  defp do_call_tool(flow, tool_ctx, tool, fc) do
    case run_before_tool_callbacks(flow.before_tool_callbacks, tool_ctx, tool, fc.args) do
      {:short_circuit, result, updated_ctx} ->
        {updated_ctx, make_response_part(fc, result)}

      {:continue, updated_ctx} ->
        execute_and_finalize(flow, updated_ctx, tool, fc)
    end
  end

  defp execute_and_finalize(flow, tool_ctx, tool, fc) do
    case Tool.run(tool, tool_ctx, fc.args) do
      {:ok, result} ->
        finalize_tool_success(flow, tool_ctx, tool, fc, result)

      {:error, reason} ->
        finalize_tool_error(flow, tool_ctx, tool, fc, reason)
    end
  end

  defp finalize_tool_success(flow, tool_ctx, tool, fc, result) do
    tool_ctx = maybe_set_transfer(tool_ctx, result)

    case run_after_tool_callbacks(flow.after_tool_callbacks, tool_ctx, tool, fc.args, result) do
      {:replaced, replaced_result, after_ctx} ->
        {after_ctx, make_response_part(fc, replaced_result)}

      {:continue, after_ctx} ->
        {after_ctx, make_response_part(fc, result)}
    end
  end

  defp maybe_set_transfer(tool_ctx, %{"transfer_to_agent" => name}) when is_binary(name) do
    %{tool_ctx | actions: %{tool_ctx.actions | transfer_to_agent: name}}
  end

  defp maybe_set_transfer(tool_ctx, _), do: tool_ctx

  defp finalize_tool_error(flow, tool_ctx, tool, fc, reason) do
    error_result = %{"error" => to_string(reason)}

    case run_tool_error_callbacks(flow.on_tool_error_callbacks, tool_ctx, tool, error_result) do
      {:recovered, recovered_result, err_ctx} ->
        {err_ctx, make_response_part(fc, recovered_result)}

      {:continue, err_ctx} ->
        {err_ctx, make_response_part(fc, error_result)}
    end
  end

  defp run_before_tool_callbacks([], tool_ctx, _tool, _args), do: {:continue, tool_ctx}

  defp run_before_tool_callbacks([callback | rest], tool_ctx, tool, args) do
    case callback.(tool_ctx, tool, args) do
      {%{} = result, updated_ctx} when not is_struct(result) -> {:short_circuit, result, updated_ctx}
      {nil, updated_ctx} -> run_before_tool_callbacks(rest, updated_ctx, tool, args)
    end
  end

  defp run_after_tool_callbacks([], tool_ctx, _tool, _args, _result), do: {:continue, tool_ctx}

  defp run_after_tool_callbacks([callback | rest], tool_ctx, tool, args, result) do
    case callback.(tool_ctx, tool, args, result) do
      {%{} = replaced, updated_ctx} when not is_struct(replaced) ->
        {:replaced, replaced, updated_ctx}

      {nil, updated_ctx} ->
        run_after_tool_callbacks(rest, updated_ctx, tool, args, result)
    end
  end

  defp run_tool_error_callbacks([], tool_ctx, _tool, _error), do: {:continue, tool_ctx}

  defp run_tool_error_callbacks([callback | rest], tool_ctx, tool, error) do
    case callback.(tool_ctx, tool, error) do
      {%{} = recovered, updated_ctx} when not is_struct(recovered) ->
        {:recovered, recovered, updated_ctx}

      {nil, updated_ctx} ->
        run_tool_error_callbacks(rest, updated_ctx, tool, error)
    end
  end

  defp make_response_part(%FunctionCall{} = fc, result) do
    %Part{
      function_response: %FunctionResponse{
        name: fc.name,
        id: fc.id,
        response: result
      }
    }
  end

  defp merge_actions(acc, new) do
    %Actions{
      state_delta: Map.merge(acc.state_delta, new.state_delta),
      artifact_delta: Map.merge(acc.artifact_delta, new.artifact_delta),
      transfer_to_agent: new.transfer_to_agent || acc.transfer_to_agent,
      escalate: acc.escalate or new.escalate,
      skip_summarization: acc.skip_summarization or new.skip_summarization
    }
  end

  defp agent_name(%InvocationContext{agent: nil}), do: nil

  defp agent_name(%InvocationContext{agent: agent}) do
    agent.__struct__.name(agent)
  end

  defp model_name(%__MODULE__{model: nil}), do: nil
  defp model_name(%__MODULE__{model: model}), do: Model.name(model)

  defp maybe_run_transfer(%Event{actions: %{transfer_to_agent: name}}, ctx)
       when is_binary(name) do
    case Tree.find_agent(ctx.root_agent, name) do
      {:ok, target_agent} ->
        transfer_ctx = InvocationContext.with_agent(ctx, target_agent)
        target_agent.__struct__.run(target_agent, transfer_ctx) |> Enum.to_list()

      :error ->
        []
    end
  end

  defp maybe_run_transfer(_event, _ctx), do: []

  defp update_ctx_from_event(ctx, %Event{actions: actions}) do
    if ctx.session && map_size(actions.state_delta) > 0 do
      updated_state = Map.merge(ctx.session.state, actions.state_delta)
      updated_session = %{ctx.session | state: updated_state}
      %{ctx | session: updated_session}
    else
      ctx
    end
  end
end
