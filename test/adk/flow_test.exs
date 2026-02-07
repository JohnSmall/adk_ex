defmodule ADK.FlowTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.InvocationContext
  alias ADK.Event
  alias ADK.Flow
  alias ADK.Model.{LlmResponse, Mock}
  alias ADK.Session
  alias ADK.Tool.FunctionTool
  alias ADK.Types.{Content, FunctionCall, Part}

  defmodule TestAgent do
    defstruct name: "flow-agent", generate_content_config: %{}, include_contents: :default,
              instruction: "", global_instruction: ""

    def name(%__MODULE__{name: n}), do: n
    def description(_), do: ""
  end

  defp make_ctx(opts \\ []) do
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: %{}, events: []}
    agent = struct(TestAgent, Keyword.get(opts, :agent_fields, %{}))

    %InvocationContext{
      agent: agent,
      session: session,
      invocation_id: "inv-1",
      run_config: %ADK.RunConfig{}
    }
  end

  defp simple_flow(model, tools \\ []) do
    %Flow{
      model: model,
      tools: tools,
      request_processors: [
        &ADK.Flow.Processors.Basic.process/3,
        &ADK.Flow.Processors.ToolProcessor.process/3,
        &ADK.Flow.Processors.Instructions.process/3,
        &ADK.Flow.Processors.Contents.process/3
      ]
    }
  end

  test "simple text response" do
    response = %LlmResponse{
      content: Content.new_from_text("model", "Hello!"),
      turn_complete: true
    }

    model = Mock.new(responses: [response])
    flow = simple_flow(model)
    ctx = make_ctx()

    events = flow |> Flow.run(ctx) |> Enum.to_list()

    assert length(events) == 1
    event = hd(events)
    assert event.author == "flow-agent"
    assert hd(event.content.parts).text == "Hello!"
    assert Event.final_response?(event)
  end

  test "tool call and response" do
    weather_tool =
      FunctionTool.new(
        name: "get_weather",
        description: "Gets weather for a city",
        parameters: %{
          "type" => "object",
          "properties" => %{"city" => %{"type" => "string"}},
          "required" => ["city"]
        },
        handler: fn _ctx, args ->
          {:ok, %{"temperature" => "20°C", "city" => args["city"]}}
        end
      )

    fc_response = %LlmResponse{
      content: %Content{
        role: "model",
        parts: [
          %Part{
            function_call: %FunctionCall{name: "get_weather", id: "call_1", args: %{"city" => "London"}}
          }
        ]
      },
      turn_complete: true
    }

    final_response = %LlmResponse{
      content: Content.new_from_text("model", "The weather in London is 20°C."),
      turn_complete: true
    }

    model = Mock.new(responses: [fc_response, final_response])
    flow = simple_flow(model, [weather_tool])
    ctx = make_ctx()

    events = flow |> Flow.run(ctx) |> Enum.to_list()

    assert length(events) == 3

    [fc_event, tool_event, final_event] = events

    assert fc_event.content.role == "model"
    assert hd(fc_event.content.parts).function_call.name == "get_weather"

    assert tool_event.content.role == "user"
    fr = hd(tool_event.content.parts).function_response
    assert fr.name == "get_weather"
    assert fr.response["temperature"] == "20°C"

    assert hd(final_event.content.parts).text == "The weather in London is 20°C."
    assert Event.final_response?(final_event)
  end

  test "tool not found returns error response" do
    fc_response = %LlmResponse{
      content: %Content{
        role: "model",
        parts: [
          %Part{
            function_call: %FunctionCall{name: "unknown_tool", id: "call_1", args: %{}}
          }
        ]
      },
      turn_complete: true
    }

    final_response = %LlmResponse{
      content: Content.new_from_text("model", "Sorry, tool not found."),
      turn_complete: true
    }

    model = Mock.new(responses: [fc_response, final_response])
    flow = simple_flow(model)
    ctx = make_ctx()

    events = flow |> Flow.run(ctx) |> Enum.to_list()

    assert length(events) == 3
    tool_event = Enum.at(events, 1)
    fr = hd(tool_event.content.parts).function_response
    assert fr.response["error"] =~ "Tool not found"
  end

  test "before_model callback short-circuits" do
    model = Mock.new()

    flow = %Flow{
      model: model,
      tools: [],
      request_processors: [&ADK.Flow.Processors.Basic.process/3],
      before_model_callbacks: [
        fn cb_ctx, _request ->
          response = %LlmResponse{
            content: Content.new_from_text("model", "Intercepted!"),
            turn_complete: true
          }

          {response, cb_ctx}
        end
      ]
    }

    ctx = make_ctx()
    events = flow |> Flow.run(ctx) |> Enum.to_list()

    assert length(events) == 1
    assert hd(hd(events).content.parts).text == "Intercepted!"
  end

  test "after_model callback replaces response" do
    response = %LlmResponse{
      content: Content.new_from_text("model", "Original"),
      turn_complete: true
    }

    model = Mock.new(responses: [response])

    flow = %Flow{
      model: model,
      tools: [],
      request_processors: [&ADK.Flow.Processors.Basic.process/3],
      after_model_callbacks: [
        fn cb_ctx, _response ->
          replaced = %LlmResponse{
            content: Content.new_from_text("model", "Replaced!"),
            turn_complete: true
          }

          {replaced, cb_ctx}
        end
      ]
    }

    ctx = make_ctx()
    events = flow |> Flow.run(ctx) |> Enum.to_list()

    assert hd(hd(events).content.parts).text == "Replaced!"
  end

  test "before_tool callback short-circuits tool execution" do
    tool =
      FunctionTool.new(
        name: "my_tool",
        description: "A tool",
        handler: fn _ctx, _args -> {:ok, %{"from" => "real_tool"}} end
      )

    fc_response = %LlmResponse{
      content: %Content{
        role: "model",
        parts: [%Part{function_call: %FunctionCall{name: "my_tool", id: "c1", args: %{}}}]
      },
      turn_complete: true
    }

    final_response = %LlmResponse{
      content: Content.new_from_text("model", "Done"),
      turn_complete: true
    }

    model = Mock.new(responses: [fc_response, final_response])

    flow = %Flow{
      model: model,
      tools: [tool],
      request_processors: [
        &ADK.Flow.Processors.Basic.process/3,
        &ADK.Flow.Processors.ToolProcessor.process/3
      ],
      before_tool_callbacks: [
        fn tool_ctx, _tool, _args ->
          {%{"from" => "intercepted"}, tool_ctx}
        end
      ]
    }

    ctx = make_ctx()
    events = flow |> Flow.run(ctx) |> Enum.to_list()

    tool_event = Enum.at(events, 1)
    fr = hd(tool_event.content.parts).function_response
    assert fr.response["from"] == "intercepted"
  end

  test "tool error is handled gracefully" do
    tool =
      FunctionTool.new(
        name: "bad_tool",
        description: "Fails",
        handler: fn _ctx, _args -> {:error, "kaboom"} end
      )

    fc_response = %LlmResponse{
      content: %Content{
        role: "model",
        parts: [%Part{function_call: %FunctionCall{name: "bad_tool", id: "c1", args: %{}}}]
      },
      turn_complete: true
    }

    final_response = %LlmResponse{
      content: Content.new_from_text("model", "Tool failed"),
      turn_complete: true
    }

    model = Mock.new(responses: [fc_response, final_response])
    flow = simple_flow(model, [tool])
    ctx = make_ctx()

    events = flow |> Flow.run(ctx) |> Enum.to_list()

    tool_event = Enum.at(events, 1)
    fr = hd(tool_event.content.parts).function_response
    assert fr.response["error"] == "kaboom"
  end

  test "max iterations produces error event" do
    # Model always returns function calls → infinite loop → max iterations
    always_fc = fn _request ->
      %LlmResponse{
        content: %Content{
          role: "model",
          parts: [%Part{function_call: %FunctionCall{name: "loop_tool", id: "c1", args: %{}}}]
        },
        turn_complete: true
      }
    end

    # Create a model that always returns function calls
    model = Mock.new(responses: List.duplicate(always_fc, 30))

    tool =
      FunctionTool.new(
        name: "loop_tool",
        description: "Loops",
        handler: fn _ctx, _args -> {:ok, %{"status" => "ok"}} end
      )

    flow = simple_flow(model, [tool])
    ctx = make_ctx()

    events = flow |> Flow.run(ctx) |> Enum.to_list()
    last = List.last(events)
    assert last.error_code == "max_iterations"
  end
end
