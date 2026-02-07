defmodule ADK.Flow.Processors.AgentTransferTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{InvocationContext, LlmAgent}
  alias ADK.Flow.Processors.AgentTransfer
  alias ADK.Model.{LlmRequest, Mock}
  alias ADK.Session

  defp make_ctx(agent, opts \\ []) do
    parent_map = Keyword.get(opts, :parent_map, %{})

    %InvocationContext{
      agent: agent,
      invocation_id: "inv-1",
      session: %Session{id: "s1", app_name: "test", user_id: "u1", state: %{}},
      parent_map: parent_map
    }
  end

  defp make_request do
    %LlmRequest{model: "test-model", config: %{}, tools: %{}}
  end

  test "adds tool for agent with sub-agents" do
    sub = %LlmAgent{name: "sub1", model: Mock.new(), description: "Helper agent"}

    agent = %LlmAgent{
      name: "parent",
      model: Mock.new(),
      sub_agents: [sub],
      disallow_transfer_to_parent: true,
      disallow_transfer_to_peers: true
    }

    ctx = make_ctx(agent)
    {:ok, request} = AgentTransfer.process(ctx, make_request(), %{})

    assert Map.has_key?(request.tools, "transfer_to_agent")
    assert request.system_instruction != nil

    # Check that system instruction mentions the sub-agent
    text = hd(request.system_instruction.parts).text
    assert text =~ "sub1"
    assert text =~ "Helper agent"
  end

  test "no-op for agent without targets" do
    agent = %LlmAgent{
      name: "solo",
      model: Mock.new(),
      sub_agents: [],
      disallow_transfer_to_parent: true,
      disallow_transfer_to_peers: true
    }

    ctx = make_ctx(agent)
    {:ok, request} = AgentTransfer.process(ctx, make_request(), %{})

    # No transfer tool should be added
    refute Map.has_key?(request.tools, "transfer_to_agent")
  end

  test "includes parent when allowed" do
    parent = %LlmAgent{name: "root", model: Mock.new(), description: "Root agent"}

    agent = %LlmAgent{
      name: "child",
      model: Mock.new(),
      sub_agents: [],
      disallow_transfer_to_parent: false,
      disallow_transfer_to_peers: true
    }

    ctx = make_ctx(agent, parent_map: %{"child" => parent})
    {:ok, request} = AgentTransfer.process(ctx, make_request(), %{})

    assert Map.has_key?(request.tools, "transfer_to_agent")
    text = hd(request.system_instruction.parts).text
    assert text =~ "root"
  end

  test "excludes parent when disallowed" do
    parent = %LlmAgent{name: "root", model: Mock.new(), description: "Root agent"}

    agent = %LlmAgent{
      name: "child",
      model: Mock.new(),
      sub_agents: [],
      disallow_transfer_to_parent: true,
      disallow_transfer_to_peers: true
    }

    ctx = make_ctx(agent, parent_map: %{"child" => parent})
    {:ok, request} = AgentTransfer.process(ctx, make_request(), %{})

    # No targets at all
    refute Map.has_key?(request.tools, "transfer_to_agent")
  end

  test "includes peers when allowed" do
    peer = %LlmAgent{name: "peer1", model: Mock.new(), description: "Peer agent"}
    agent = %LlmAgent{name: "child", model: Mock.new(), sub_agents: [], disallow_transfer_to_peers: false, disallow_transfer_to_parent: true}
    parent = %LlmAgent{name: "root", model: Mock.new(), sub_agents: [agent, peer]}

    ctx = make_ctx(agent, parent_map: %{"child" => parent, "peer1" => parent})
    {:ok, request} = AgentTransfer.process(ctx, make_request(), %{})

    assert Map.has_key?(request.tools, "transfer_to_agent")
    text = hd(request.system_instruction.parts).text
    assert text =~ "peer1"
    refute text =~ "child"
  end

  test "excludes peers when disallowed" do
    peer = %LlmAgent{name: "peer1", model: Mock.new(), description: "Peer agent"}
    agent = %LlmAgent{name: "child", model: Mock.new(), sub_agents: [], disallow_transfer_to_peers: true, disallow_transfer_to_parent: true}
    parent = %LlmAgent{name: "root", model: Mock.new(), sub_agents: [agent, peer]}

    ctx = make_ctx(agent, parent_map: %{"child" => parent, "peer1" => parent})
    {:ok, request} = AgentTransfer.process(ctx, make_request(), %{})

    refute Map.has_key?(request.tools, "transfer_to_agent")
  end
end
