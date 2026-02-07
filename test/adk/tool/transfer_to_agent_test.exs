defmodule ADK.Tool.TransferToAgentTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.CallbackContext
  alias ADK.Agent.InvocationContext
  alias ADK.Tool.Context, as: ToolContext
  alias ADK.Tool.TransferToAgent

  defp make_tool_ctx do
    cb_ctx = CallbackContext.new(%InvocationContext{invocation_id: "inv-1"})
    ToolContext.new(cb_ctx, "fc-1")
  end

  test "returns transfer target in result" do
    tool = %TransferToAgent{}
    {:ok, result} = TransferToAgent.run(tool, make_tool_ctx(), %{"agent_name" => "sub_agent"})
    assert result == %{"transfer_to_agent" => "sub_agent"}
  end

  test "rejects nil agent_name" do
    tool = %TransferToAgent{}
    assert {:error, _} = TransferToAgent.run(tool, make_tool_ctx(), %{})
  end

  test "rejects empty agent_name" do
    tool = %TransferToAgent{}
    assert {:error, _} = TransferToAgent.run(tool, make_tool_ctx(), %{"agent_name" => ""})
  end

  test "declaration has correct structure" do
    tool = %TransferToAgent{}
    decl = TransferToAgent.declaration(tool)
    assert decl["name"] == "transfer_to_agent"
    assert decl["parameters"]["required"] == ["agent_name"]
  end

  test "name and description" do
    tool = %TransferToAgent{}
    assert TransferToAgent.name(tool) == "transfer_to_agent"
    assert is_binary(TransferToAgent.description(tool))
  end
end
