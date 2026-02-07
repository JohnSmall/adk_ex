defmodule ADK.Tool.Context do
  @moduledoc """
  Context passed to tool execution.

  Wraps a `CallbackContext` and adds `function_call_id` and its own
  `Actions`. Each tool call gets its own `ToolContext` with independent
  actions that are merged after all tool calls complete.
  """

  alias ADK.Agent.CallbackContext
  alias ADK.Event.Actions

  @type t :: %__MODULE__{
          callback_context: CallbackContext.t(),
          function_call_id: String.t() | nil,
          actions: Actions.t()
        }

  defstruct [
    :callback_context,
    :function_call_id,
    actions: %Actions{}
  ]

  @doc "Creates a new tool context from a callback context and function call ID."
  @spec new(CallbackContext.t(), String.t() | nil) :: t()
  def new(%CallbackContext{} = cb_ctx, function_call_id \\ nil) do
    %__MODULE__{
      callback_context: cb_ctx,
      function_call_id: function_call_id,
      actions: %Actions{}
    }
  end

  @doc "Gets a value from session state, checking tool actions then callback actions then session."
  @spec get_state(t(), String.t()) :: any()
  def get_state(%__MODULE__{actions: actions, callback_context: cb_ctx}, key) do
    case Map.fetch(actions.state_delta, key) do
      {:ok, value} -> value
      :error -> CallbackContext.get_state(cb_ctx, key)
    end
  end

  @doc "Sets a value in the tool actions state_delta."
  @spec set_state(t(), String.t(), any()) :: t()
  def set_state(%__MODULE__{actions: actions} = ctx, key, value) do
    new_delta = Map.put(actions.state_delta, key, value)
    %{ctx | actions: %{actions | state_delta: new_delta}}
  end

  @doc "Returns the agent name from the underlying callback context."
  @spec agent_name(t()) :: String.t() | nil
  def agent_name(%__MODULE__{callback_context: cb_ctx}) do
    CallbackContext.agent_name(cb_ctx)
  end
end
