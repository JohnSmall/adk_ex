defmodule ADK.RunnerTest do
  use ExUnit.Case

  alias ADK.Agent.LlmAgent
  alias ADK.Model.{LlmResponse, Mock}
  alias ADK.Runner
  alias ADK.Tool.FunctionTool
  alias ADK.Types.{Content, FunctionCall, Part}

  setup do
    name = :"session_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = ADK.Session.InMemory.start_link(name: name, table_prefix: name)
    {:ok, session_service: name}
  end

  defp make_runner(ctx, agent) do
    {:ok, runner} =
      Runner.new(
        app_name: "test-app",
        root_agent: agent,
        session_service: ctx[:session_service]
      )

    runner
  end

  test "simple text response end-to-end", ctx do
    response = %LlmResponse{
      content: Content.new_from_text("model", "Hello from the runner!"),
      turn_complete: true
    }

    model = Mock.new(responses: [response])
    agent = %LlmAgent{name: "runner-agent", model: model}
    runner = make_runner(ctx, agent)

    user_msg = Content.new_from_text("user", "Hi there")

    events =
      runner
      |> Runner.run("user-1", "session-1", user_msg)
      |> Enum.to_list()

    assert events != []
    final = List.last(events)
    assert hd(final.content.parts).text == "Hello from the runner!"
  end

  test "events are persisted to session", ctx do
    response = %LlmResponse{
      content: Content.new_from_text("model", "Saved!"),
      turn_complete: true
    }

    model = Mock.new(responses: [response])
    agent = %LlmAgent{name: "persist-agent", model: model}
    runner = make_runner(ctx, agent)

    user_msg = Content.new_from_text("user", "Hello")

    _events =
      runner
      |> Runner.run("user-1", "session-1", user_msg)
      |> Enum.to_list()

    {:ok, session} =
      ADK.Session.InMemory.get(ctx[:session_service],
        app_name: "test-app",
        user_id: "user-1",
        session_id: "session-1"
      )

    assert length(session.events) >= 2
    assert hd(session.events).author == "user"
    assert hd(hd(session.events).content.parts).text == "Hello"
  end

  test "tool call end-to-end", ctx do
    weather_tool =
      FunctionTool.new(
        name: "get_weather",
        description: "Gets weather",
        handler: fn _ctx, args ->
          {:ok, %{"temp" => "18°C", "city" => args["city"]}}
        end
      )

    fc_response = %LlmResponse{
      content: %Content{
        role: "model",
        parts: [
          %Part{function_call: %FunctionCall{name: "get_weather", id: "c1", args: %{"city" => "London"}}}
        ]
      },
      turn_complete: true
    }

    final_response = %LlmResponse{
      content: Content.new_from_text("model", "It's 18°C in London."),
      turn_complete: true
    }

    model = Mock.new(responses: [fc_response, final_response])

    agent = %LlmAgent{
      name: "weather-agent",
      model: model,
      tools: [weather_tool],
      instruction: "You are a weather bot."
    }

    runner = make_runner(ctx, agent)
    user_msg = Content.new_from_text("user", "What's the weather in London?")

    events =
      runner
      |> Runner.run("user-1", "session-1", user_msg)
      |> Enum.to_list()

    final = List.last(events)
    assert final.content != nil
    assert hd(final.content.parts).text == "It's 18°C in London."

    {:ok, session} =
      ADK.Session.InMemory.get(ctx[:session_service],
        app_name: "test-app",
        user_id: "user-1",
        session_id: "session-1"
      )

    assert length(session.events) >= 3
  end

  test "session auto-creation", ctx do
    response = %LlmResponse{
      content: Content.new_from_text("model", "Created!"),
      turn_complete: true
    }

    model = Mock.new(responses: [response])
    agent = %LlmAgent{name: "auto-agent", model: model}
    runner = make_runner(ctx, agent)

    assert {:error, :not_found} =
             ADK.Session.InMemory.get(ctx[:session_service],
               app_name: "test-app",
               user_id: "user-1",
               session_id: "auto-session"
             )

    _events =
      runner
      |> Runner.run("user-1", "auto-session", Content.new_from_text("user", "Hi"))
      |> Enum.to_list()

    {:ok, session} =
      ADK.Session.InMemory.get(ctx[:session_service],
        app_name: "test-app",
        user_id: "user-1",
        session_id: "auto-session"
      )

    assert session.id == "auto-session"
  end

  test "duplicate agent names rejected" do
    inner = %LlmAgent{name: "dup", model: Mock.new()}
    outer = %LlmAgent{name: "dup", model: Mock.new(), sub_agents: [inner]}

    assert {:error, "duplicate agent name: dup"} =
             Runner.new(
               app_name: "test",
               root_agent: outer,
               session_service: :not_used
             )
  end

  test "multi-turn conversation", ctx do
    r1 = %LlmResponse{
      content: Content.new_from_text("model", "First reply"),
      turn_complete: true
    }

    r2 = %LlmResponse{
      content: Content.new_from_text("model", "Second reply"),
      turn_complete: true
    }

    # Use a shared stateful mock for multi-turn
    model = Mock.new(responses: [r1, r2])
    agent = %LlmAgent{name: "multi-agent", model: model}
    runner = make_runner(ctx, agent)

    events1 =
      runner
      |> Runner.run("user-1", "session-1", Content.new_from_text("user", "Hello"))
      |> Enum.to_list()

    assert hd(List.last(events1).content.parts).text == "First reply"

    events2 =
      runner
      |> Runner.run("user-1", "session-1", Content.new_from_text("user", "Follow up"))
      |> Enum.to_list()

    assert hd(List.last(events2).content.parts).text == "Second reply"

    {:ok, session} =
      ADK.Session.InMemory.get(ctx[:session_service],
        app_name: "test-app",
        user_id: "user-1",
        session_id: "session-1"
      )

    assert length(session.events) >= 4
  end
end
