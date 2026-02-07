defmodule ADK.Agent.AgentTransferTest do
  use ExUnit.Case

  alias ADK.Agent.LlmAgent
  alias ADK.Model.{LlmResponse, Mock}
  alias ADK.Runner
  alias ADK.Types.{Content, FunctionCall, Part}

  setup do
    name = :"session_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = ADK.Session.InMemory.start_link(name: name, table_prefix: name)
    {:ok, session_service: name}
  end

  test "LLM calls transfer_to_agent, sub-agent runs", ctx do
    # Parent LLM first calls transfer_to_agent tool, then sub-agent replies
    transfer_response = %LlmResponse{
      content: %Content{
        role: "model",
        parts: [
          %Part{
            function_call: %FunctionCall{
              name: "transfer_to_agent",
              id: "tc1",
              args: %{"agent_name" => "helper"}
            }
          }
        ]
      },
      turn_complete: true
    }

    parent_model = Mock.new(responses: [transfer_response])

    helper_response = %LlmResponse{
      content: Content.new_from_text("model", "I'm the helper!"),
      turn_complete: true
    }

    helper_model = Mock.new(responses: [helper_response])

    helper = %LlmAgent{
      name: "helper",
      model: helper_model,
      description: "A helper agent"
    }

    parent = %LlmAgent{
      name: "parent",
      model: parent_model,
      sub_agents: [helper]
    }

    {:ok, runner} =
      Runner.new(
        app_name: "test-app",
        root_agent: parent,
        session_service: ctx[:session_service]
      )

    events =
      runner
      |> Runner.run("user-1", "session-1", Content.new_from_text("user", "Help me"))
      |> Enum.to_list()

    # Should have: model event (transfer call), tool event (tool response), helper events
    assert length(events) >= 3

    # The last event should be from the helper agent
    final = List.last(events)
    assert hd(final.content.parts).text == "I'm the helper!"
  end

  test "runner finds transferred-to agent on next turn", ctx do
    # First turn: parent transfers to helper
    transfer_response = %LlmResponse{
      content: %Content{
        role: "model",
        parts: [
          %Part{
            function_call: %FunctionCall{
              name: "transfer_to_agent",
              id: "tc1",
              args: %{"agent_name" => "helper"}
            }
          }
        ]
      },
      turn_complete: true
    }

    helper_response1 = %LlmResponse{
      content: Content.new_from_text("model", "Helper turn 1"),
      turn_complete: true
    }

    helper_response2 = %LlmResponse{
      content: Content.new_from_text("model", "Helper turn 2"),
      turn_complete: true
    }

    parent_model = Mock.new(responses: [transfer_response])
    helper_model = Mock.new(responses: [helper_response1, helper_response2])

    helper = %LlmAgent{
      name: "helper",
      model: helper_model,
      description: "A helper"
    }

    parent = %LlmAgent{
      name: "parent",
      model: parent_model,
      sub_agents: [helper]
    }

    {:ok, runner} =
      Runner.new(
        app_name: "test-app",
        root_agent: parent,
        session_service: ctx[:session_service]
      )

    # Turn 1: transfer happens
    _events1 =
      runner
      |> Runner.run("user-1", "session-1", Content.new_from_text("user", "Help"))
      |> Enum.to_list()

    # Turn 2: should resume with helper (since it was transferred to)
    events2 =
      runner
      |> Runner.run("user-1", "session-1", Content.new_from_text("user", "More help"))
      |> Enum.to_list()

    final = List.last(events2)
    assert hd(final.content.parts).text == "Helper turn 2"
  end

  test "transfer to nonexistent agent is handled gracefully", ctx do
    transfer_response = %LlmResponse{
      content: %Content{
        role: "model",
        parts: [
          %Part{
            function_call: %FunctionCall{
              name: "transfer_to_agent",
              id: "tc1",
              args: %{"agent_name" => "nonexistent"}
            }
          }
        ]
      },
      turn_complete: true
    }

    # After the transfer tool call returns, the flow will loop and call the model again
    # The second response is a normal text response
    followup_response = %LlmResponse{
      content: Content.new_from_text("model", "No agent found, I'll handle it"),
      turn_complete: true
    }

    parent_model = Mock.new(responses: [transfer_response, followup_response])

    parent = %LlmAgent{
      name: "parent",
      model: parent_model,
      sub_agents: []
    }

    {:ok, runner} =
      Runner.new(
        app_name: "test-app",
        root_agent: parent,
        session_service: ctx[:session_service]
      )

    # Should not crash
    events =
      runner
      |> Runner.run("user-1", "session-1", Content.new_from_text("user", "Transfer me"))
      |> Enum.to_list()

    assert events != []
  end
end
