defmodule ADK.Tool.ContextTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{CallbackContext, InvocationContext}
  alias ADK.Session
  alias ADK.Tool.Context, as: ToolContext

  defp make_context(state \\ %{}) do
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: state}
    ctx = %InvocationContext{session: session}
    cb_ctx = CallbackContext.new(ctx)
    ToolContext.new(cb_ctx, "call_123")
  end

  test "new creates context with function_call_id" do
    tool_ctx = make_context()
    assert tool_ctx.function_call_id == "call_123"
    assert tool_ctx.actions.state_delta == %{}
  end

  test "get_state reads from session" do
    tool_ctx = make_context(%{"city" => "London"})
    assert ToolContext.get_state(tool_ctx, "city") == "London"
  end

  test "set_state writes to actions" do
    tool_ctx = make_context()
    updated = ToolContext.set_state(tool_ctx, "result", 42)
    assert updated.actions.state_delta["result"] == 42
  end

  test "get_state prefers tool actions over session" do
    tool_ctx = make_context(%{"key" => "session_val"})
    updated = ToolContext.set_state(tool_ctx, "key", "tool_val")
    assert ToolContext.get_state(updated, "key") == "tool_val"
  end

  test "get_state falls through callback context to session" do
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: %{"x" => 1}}
    ctx = %InvocationContext{session: session}
    cb_ctx = CallbackContext.set_state(CallbackContext.new(ctx), "y", 2)
    tool_ctx = ToolContext.new(cb_ctx, "call_1")

    assert ToolContext.get_state(tool_ctx, "x") == 1
    assert ToolContext.get_state(tool_ctx, "y") == 2
  end

  test "agent_name delegates to callback context" do
    # Without agent, returns nil
    tool_ctx = make_context()
    assert ToolContext.agent_name(tool_ctx) == nil
  end
end
