defmodule ADK.Agent.LlmAgentTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{InvocationContext, LlmAgent}
  alias ADK.Model.{LlmResponse, Mock}
  alias ADK.Session
  alias ADK.Tool.FunctionTool
  alias ADK.Types.{Content, FunctionCall, Part}

  defp make_ctx(agent) do
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: %{}, events: []}

    %InvocationContext{
      agent: agent,
      session: session,
      invocation_id: "inv-1",
      run_config: %ADK.RunConfig{}
    }
  end

  test "name and description" do
    agent = %LlmAgent{
      name: "assistant",
      model: Mock.new(),
      description: "A helpful assistant"
    }

    assert LlmAgent.name(agent) == "assistant"
    assert LlmAgent.description(agent) == "A helpful assistant"
  end

  test "sub_agents defaults to empty" do
    agent = %LlmAgent{name: "a", model: Mock.new()}
    assert LlmAgent.sub_agents(agent) == []
  end

  test "simple text response" do
    response = %LlmResponse{
      content: Content.new_from_text("model", "Hi there!"),
      turn_complete: true
    }

    model = Mock.new(responses: [response])
    agent = %LlmAgent{name: "bot", model: model}
    ctx = make_ctx(agent)

    events = agent |> LlmAgent.run(ctx) |> Enum.to_list()

    assert events != []
    final = List.last(events)
    assert hd(final.content.parts).text == "Hi there!"
    assert final.author == "bot"
  end

  test "tool call flow" do
    weather_tool =
      FunctionTool.new(
        name: "get_weather",
        description: "Gets weather",
        handler: fn _ctx, args ->
          {:ok, %{"temp" => "22°C", "city" => args["city"]}}
        end
      )

    fc_response = %LlmResponse{
      content: %Content{
        role: "model",
        parts: [
          %Part{function_call: %FunctionCall{name: "get_weather", id: "c1", args: %{"city" => "Paris"}}}
        ]
      },
      turn_complete: true
    }

    final_response = %LlmResponse{
      content: Content.new_from_text("model", "Paris is 22°C"),
      turn_complete: true
    }

    model = Mock.new(responses: [fc_response, final_response])

    agent = %LlmAgent{
      name: "weather-bot",
      model: model,
      tools: [weather_tool],
      instruction: "You are a weather assistant."
    }

    ctx = make_ctx(agent)
    events = agent |> LlmAgent.run(ctx) |> Enum.to_list()

    texts =
      events
      |> Enum.filter(fn e -> e.content && e.content.role == "model" end)
      |> Enum.flat_map(fn e -> Enum.map(e.content.parts, & &1.text) end)
      |> Enum.reject(&is_nil/1)

    assert "Paris is 22°C" in texts
  end

  test "before_agent_callback short-circuits" do
    model = Mock.new()

    agent = %LlmAgent{
      name: "guarded",
      model: model,
      before_agent_callbacks: [
        fn cb_ctx ->
          {Content.new_from_text("model", "Blocked by callback"), cb_ctx}
        end
      ]
    }

    ctx = make_ctx(agent)
    events = agent |> LlmAgent.run(ctx) |> Enum.to_list()

    assert length(events) == 1
    assert hd(hd(events).content.parts).text == "Blocked by callback"
  end

  test "after_agent_callback runs" do
    response = %LlmResponse{
      content: Content.new_from_text("model", "Normal response"),
      turn_complete: true
    }

    model = Mock.new(responses: [response])
    after_ran = :ets.new(:test_after, [:set, :public])

    agent = %LlmAgent{
      name: "tracked",
      model: model,
      after_agent_callbacks: [
        fn cb_ctx ->
          :ets.insert(after_ran, {:ran, true})
          {nil, cb_ctx}
        end
      ]
    }

    ctx = make_ctx(agent)
    _events = agent |> LlmAgent.run(ctx) |> Enum.to_list()

    assert [{:ran, true}] = :ets.lookup(after_ran, :ran)
    :ets.delete(after_ran)
  end

  test "output_key saves last model text to state_delta" do
    response = %LlmResponse{
      content: Content.new_from_text("model", "The answer is 42"),
      turn_complete: true
    }

    model = Mock.new(responses: [response])

    agent = %LlmAgent{
      name: "keyed",
      model: model,
      output_key: "answer"
    }

    ctx = make_ctx(agent)
    events = agent |> LlmAgent.run(ctx) |> Enum.to_list()

    last = List.last(events)
    assert last.actions.state_delta["answer"] == "The answer is 42"
  end
end
