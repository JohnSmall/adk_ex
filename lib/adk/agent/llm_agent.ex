defmodule ADK.Agent.LlmAgent do
  @moduledoc """
  An agent backed by a large language model.

  Combines a model, tools, instructions, and callbacks into a complete
  agent that can have multi-turn conversations and call tools.
  """

  @behaviour ADK.Agent

  alias ADK.Agent.{CallbackContext, InvocationContext}
  alias ADK.Event
  alias ADK.Flow
  alias ADK.Flow.Processors.{AgentTransfer, Basic, Contents, Instructions, ToolProcessor}
  alias ADK.Types.Content

  @type t :: %__MODULE__{
          name: String.t(),
          model: struct(),
          description: String.t(),
          instruction: String.t(),
          global_instruction: String.t(),
          instruction_provider: (InvocationContext.t() -> String.t()) | nil,
          global_instruction_provider: (InvocationContext.t() -> String.t()) | nil,
          output_key: String.t() | nil,
          output_schema: map() | nil,
          generate_content_config: map(),
          tools: [struct()],
          sub_agents: [struct()],
          include_contents: :default | :none,
          disallow_transfer_to_parent: boolean(),
          disallow_transfer_to_peers: boolean(),
          before_agent_callbacks: [term()],
          after_agent_callbacks: [term()],
          before_model_callbacks: [Flow.before_model_callback()],
          after_model_callbacks: [Flow.after_model_callback()],
          on_model_error_callbacks: [term()],
          before_tool_callbacks: [Flow.before_tool_callback()],
          after_tool_callbacks: [Flow.after_tool_callback()],
          on_tool_error_callbacks: [term()]
        }

  @enforce_keys [:name, :model]
  defstruct [
    :name,
    :model,
    :instruction_provider,
    :global_instruction_provider,
    :output_key,
    :output_schema,
    description: "",
    instruction: "",
    global_instruction: "",
    generate_content_config: %{},
    tools: [],
    sub_agents: [],
    include_contents: :default,
    disallow_transfer_to_parent: false,
    disallow_transfer_to_peers: false,
    before_agent_callbacks: [],
    after_agent_callbacks: [],
    before_model_callbacks: [],
    after_model_callbacks: [],
    on_model_error_callbacks: [],
    before_tool_callbacks: [],
    after_tool_callbacks: [],
    on_tool_error_callbacks: []
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
      fn -> {:before, agent, ctx} end,
      &next/1,
      fn _ -> :ok end
    )
  end

  defp next(:done), do: {:halt, :done}

  defp next({:before, agent, ctx}) do
    cb_ctx = CallbackContext.new(ctx)

    case run_callbacks(agent.before_agent_callbacks, cb_ctx) do
      {:short_circuit, content, updated_cb_ctx} ->
        event = make_callback_event(ctx, agent, content, updated_cb_ctx)
        {[event], :done}

      {:continue, _cb_ctx} ->
        flow = build_flow(agent)
        events = flow |> Flow.run(ctx) |> Enum.to_list()
        events = maybe_save_output(events, agent)
        {events, {:after, agent, ctx}}
    end
  end

  defp next({:after, agent, ctx}) do
    cb_ctx = CallbackContext.new(ctx)

    case run_callbacks(agent.after_agent_callbacks, cb_ctx) do
      {:short_circuit, content, updated_cb_ctx} ->
        event = make_callback_event(ctx, agent, content, updated_cb_ctx)
        {[event], :done}

      {:continue, _cb_ctx} ->
        {[], :done}
    end
  end

  defp build_flow(agent) do
    %Flow{
      model: agent.model,
      tools: agent.tools,
      request_processors: [
        &Basic.process/3,
        &ToolProcessor.process/3,
        &Instructions.process/3,
        &AgentTransfer.process/3,
        &Contents.process/3
      ],
      before_model_callbacks: agent.before_model_callbacks,
      after_model_callbacks: agent.after_model_callbacks,
      on_model_error_callbacks: agent.on_model_error_callbacks,
      before_tool_callbacks: agent.before_tool_callbacks,
      after_tool_callbacks: agent.after_tool_callbacks,
      on_tool_error_callbacks: agent.on_tool_error_callbacks
    }
  end

  defp run_callbacks([], cb_ctx), do: {:continue, cb_ctx}

  defp run_callbacks([callback | rest], cb_ctx) do
    case callback.(cb_ctx) do
      {%Content{} = content, updated_ctx} -> {:short_circuit, content, updated_ctx}
      {nil, updated_ctx} -> run_callbacks(rest, updated_ctx)
    end
  end

  defp make_callback_event(ctx, agent, content, cb_ctx) do
    Event.new(
      invocation_id: ctx.invocation_id,
      branch: ctx.branch,
      author: agent.name,
      content: content,
      actions: cb_ctx.actions
    )
  end

  defp maybe_save_output(events, %__MODULE__{output_key: nil}), do: events

  defp maybe_save_output(events, %__MODULE__{output_key: key}) do
    case find_last_model_text(events) do
      nil ->
        events

      text ->
        # Update the last event's state_delta with the output key
        {init, [last]} = Enum.split(events, -1)
        actions = %{last.actions | state_delta: Map.put(last.actions.state_delta, key, text)}
        init ++ [%{last | actions: actions}]
    end
  end

  defp find_last_model_text(events) do
    events
    |> Enum.reverse()
    |> Enum.find_value(fn event ->
      if event.content && event.content.role == "model" do
        extract_text(event.content)
      end
    end)
  end

  defp extract_text(%Content{parts: parts}) do
    text =
      parts
      |> Enum.map_join("", fn part ->
        if part.text, do: part.text, else: ""
      end)

    if text == "", do: nil, else: text
  end
end
