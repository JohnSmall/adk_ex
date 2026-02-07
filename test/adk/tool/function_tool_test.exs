defmodule ADK.Tool.FunctionToolTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{CallbackContext, InvocationContext}
  alias ADK.Tool
  alias ADK.Tool.Context, as: ToolContext
  alias ADK.Tool.FunctionTool

  defp make_tool_context do
    ctx = %InvocationContext{}
    cb_ctx = CallbackContext.new(ctx)
    ToolContext.new(cb_ctx, "call_123")
  end

  test "name and description" do
    tool =
      FunctionTool.new(
        name: "get_weather",
        description: "Gets the weather for a city",
        handler: fn _ctx, _args -> {:ok, %{}} end
      )

    assert Tool.name(tool) == "get_weather"
    assert Tool.description(tool) == "Gets the weather for a city"
  end

  test "declaration without parameters" do
    tool =
      FunctionTool.new(
        name: "ping",
        description: "Pings the server",
        handler: fn _ctx, _args -> {:ok, %{"status" => "ok"}} end
      )

    decl = Tool.declaration(tool)
    assert decl["name"] == "ping"
    assert decl["description"] == "Pings the server"
    refute Map.has_key?(decl, "parameters")
  end

  test "declaration with parameters" do
    tool =
      FunctionTool.new(
        name: "get_weather",
        description: "Gets weather",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "city" => %{"type" => "string", "description" => "City name"}
          },
          "required" => ["city"]
        },
        handler: fn _ctx, _args -> {:ok, %{}} end
      )

    decl = Tool.declaration(tool)
    assert decl["parameters"]["properties"]["city"]["type"] == "string"
  end

  test "run calls handler with context and args" do
    tool =
      FunctionTool.new(
        name: "add",
        description: "Adds two numbers",
        handler: fn _ctx, args ->
          result = Map.get(args, "a", 0) + Map.get(args, "b", 0)
          {:ok, %{"result" => result}}
        end
      )

    tool_ctx = make_tool_context()
    assert {:ok, %{"result" => 5}} = Tool.run(tool, tool_ctx, %{"a" => 2, "b" => 3})
  end

  test "run returns error tuple" do
    tool =
      FunctionTool.new(
        name: "fail",
        description: "Always fails",
        handler: fn _ctx, _args -> {:error, "something went wrong"} end
      )

    tool_ctx = make_tool_context()
    assert {:error, "something went wrong"} = Tool.run(tool, tool_ctx, %{})
  end

  test "run catches exceptions" do
    tool =
      FunctionTool.new(
        name: "crasher",
        description: "Crashes",
        handler: fn _ctx, _args -> raise "boom" end
      )

    tool_ctx = make_tool_context()
    assert {:error, "boom"} = Tool.run(tool, tool_ctx, %{})
  end

  test "long_running? defaults to false" do
    tool =
      FunctionTool.new(
        name: "quick",
        description: "Quick tool",
        handler: fn _ctx, _args -> {:ok, %{}} end
      )

    assert Tool.long_running?(tool) == false
  end

  test "long_running? can be set to true" do
    tool =
      FunctionTool.new(
        name: "slow",
        description: "Slow tool",
        handler: fn _ctx, _args -> {:ok, %{}} end,
        is_long_running: true
      )

    assert Tool.long_running?(tool) == true
  end
end
