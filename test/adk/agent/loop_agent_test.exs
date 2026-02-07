defmodule ADK.Agent.LoopAgentTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{Config, CustomAgent, InvocationContext, LoopAgent}
  alias ADK.Event
  alias ADK.Session
  alias ADK.Types.Content

  defp make_ctx do
    %InvocationContext{
      invocation_id: "inv-loop",
      branch: nil,
      session: %Session{
        id: "sess-1",
        app_name: "test",
        user_id: "user-1",
        state: %{}
      }
    }
  end

  defp make_agent(name, opts \\ []) do
    run_fn = Keyword.get(opts, :run)
    actions = Keyword.get(opts, :actions, %ADK.Event.Actions{})

    CustomAgent.new(%Config{
      name: name,
      run:
        run_fn ||
          fn _ctx ->
            [
              Event.new(
                content: Content.new_from_text("model", "#{name} done"),
                author: name,
                actions: actions
              )
            ]
          end
    })
  end

  test "single sub-agent, max_iterations=1" do
    sub = make_agent("step1")
    loop = %LoopAgent{name: "loop", sub_agents: [sub], max_iterations: 1}

    events = loop |> LoopAgent.run(make_ctx()) |> Enum.to_list()
    assert length(events) == 1
    assert hd(hd(events).content.parts).text == "step1 done"
  end

  test "two sub-agents run in order, max_iterations=1" do
    sub1 = make_agent("step1")
    sub2 = make_agent("step2")
    loop = %LoopAgent{name: "loop", sub_agents: [sub1, sub2], max_iterations: 1}

    events = loop |> LoopAgent.run(make_ctx()) |> Enum.to_list()
    assert length(events) == 2
    texts = Enum.map(events, fn e -> hd(e.content.parts).text end)
    assert texts == ["step1 done", "step2 done"]
  end

  test "max_iterations=2 runs twice" do
    sub = make_agent("step1")
    loop = %LoopAgent{name: "loop", sub_agents: [sub], max_iterations: 2}

    events = loop |> LoopAgent.run(make_ctx()) |> Enum.to_list()
    assert length(events) == 2
  end

  test "escalation terminates early" do
    escalating = make_agent("esc", actions: %ADK.Event.Actions{escalate: true})
    after_esc = make_agent("after")
    loop = %LoopAgent{name: "loop", sub_agents: [escalating, after_esc], max_iterations: 1}

    events = loop |> LoopAgent.run(make_ctx()) |> Enum.to_list()
    # Only the escalating agent's event; after_esc should NOT run
    assert length(events) == 1
    assert hd(hd(events).content.parts).text == "esc done"
  end

  test "max_iterations=0 with stateful agent that escalates on 3rd call" do
    counter = :counters.new(1, [:atomics])

    sub =
      make_agent("counter_agent",
        run: fn _ctx ->
          :counters.add(counter, 1, 1)
          count = :counters.get(counter, 1)
          actions = if count >= 3, do: %ADK.Event.Actions{escalate: true}, else: %ADK.Event.Actions{}

          [
            Event.new(
              content: Content.new_from_text("model", "count=#{count}"),
              author: "counter_agent",
              actions: actions
            )
          ]
        end
      )

    loop = %LoopAgent{name: "loop", sub_agents: [sub], max_iterations: 0}
    events = loop |> LoopAgent.run(make_ctx()) |> Enum.to_list()

    assert length(events) == 3
    texts = Enum.map(events, fn e -> hd(e.content.parts).text end)
    assert texts == ["count=1", "count=2", "count=3"]
  end

  test "state propagation between sub-agents within iteration" do
    writer =
      make_agent("writer",
        run: fn _ctx ->
          [
            Event.new(
              content: Content.new_from_text("model", "wrote"),
              author: "writer",
              actions: %ADK.Event.Actions{state_delta: %{"shared_key" => "hello"}}
            )
          ]
        end
      )

    reader =
      make_agent("reader",
        run: fn ctx ->
          val = Map.get(ctx.session.state, "shared_key", "missing")

          [
            Event.new(
              content: Content.new_from_text("model", "read: #{val}"),
              author: "reader"
            )
          ]
        end
      )

    loop = %LoopAgent{name: "loop", sub_agents: [writer, reader], max_iterations: 1}
    events = loop |> LoopAgent.run(make_ctx()) |> Enum.to_list()

    assert length(events) == 2
    reader_text = hd(List.last(events).content.parts).text
    assert reader_text == "read: hello"
  end

  test "name/1, description/1, sub_agents/1" do
    sub = make_agent("child")

    loop = %LoopAgent{
      name: "my-loop",
      description: "A loop",
      sub_agents: [sub]
    }

    assert LoopAgent.name(loop) == "my-loop"
    assert LoopAgent.description(loop) == "A loop"
    assert LoopAgent.sub_agents(loop) == [sub]
  end
end
