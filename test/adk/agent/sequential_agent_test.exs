defmodule ADK.Agent.SequentialAgentTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{Config, CustomAgent, InvocationContext, SequentialAgent}
  alias ADK.Event
  alias ADK.Session
  alias ADK.Types.Content

  defp make_ctx do
    %InvocationContext{
      invocation_id: "inv-seq",
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

  test "two sub-agents run in order" do
    sub1 = make_agent("first")
    sub2 = make_agent("second")
    seq = %SequentialAgent{name: "seq", sub_agents: [sub1, sub2]}

    events = seq |> SequentialAgent.run(make_ctx()) |> Enum.to_list()
    assert length(events) == 2
    texts = Enum.map(events, fn e -> hd(e.content.parts).text end)
    assert texts == ["first done", "second done"]
  end

  test "three sub-agents, middle escalates, third doesn't run" do
    sub1 = make_agent("a")
    sub2 = make_agent("b", actions: %ADK.Event.Actions{escalate: true})
    sub3 = make_agent("c")
    seq = %SequentialAgent{name: "seq", sub_agents: [sub1, sub2, sub3]}

    events = seq |> SequentialAgent.run(make_ctx()) |> Enum.to_list()
    authors = Enum.map(events, & &1.author)
    assert authors == ["a", "b"]
  end

  test "state flows between sub-agents" do
    writer =
      make_agent("w",
        run: fn _ctx ->
          [
            Event.new(
              content: Content.new_from_text("model", "wrote"),
              author: "w",
              actions: %ADK.Event.Actions{state_delta: %{"x" => 42}}
            )
          ]
        end
      )

    reader =
      make_agent("r",
        run: fn ctx ->
          val = Map.get(ctx.session.state, "x", "none")

          [
            Event.new(
              content: Content.new_from_text("model", "x=#{val}"),
              author: "r"
            )
          ]
        end
      )

    seq = %SequentialAgent{name: "seq", sub_agents: [writer, reader]}
    events = seq |> SequentialAgent.run(make_ctx()) |> Enum.to_list()
    reader_text = hd(List.last(events).content.parts).text
    assert reader_text == "x=42"
  end

  test "name/1, description/1, sub_agents/1" do
    sub = make_agent("child")

    seq = %SequentialAgent{
      name: "my-seq",
      description: "A sequence",
      sub_agents: [sub]
    }

    assert SequentialAgent.name(seq) == "my-seq"
    assert SequentialAgent.description(seq) == "A sequence"
    assert SequentialAgent.sub_agents(seq) == [sub]
  end
end
