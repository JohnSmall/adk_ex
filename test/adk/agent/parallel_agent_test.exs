defmodule ADK.Agent.ParallelAgentTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{Config, CustomAgent, InvocationContext, ParallelAgent}
  alias ADK.Event
  alias ADK.Session
  alias ADK.Types.Content

  defp make_ctx(opts \\ []) do
    %InvocationContext{
      invocation_id: "inv-par",
      branch: Keyword.get(opts, :branch),
      session: %Session{
        id: "sess-1",
        app_name: "test",
        user_id: "user-1",
        state: %{}
      }
    }
  end

  defp make_agent(name) do
    CustomAgent.new(%Config{
      name: name,
      run: fn ctx ->
        [
          Event.new(
            content: Content.new_from_text("model", "#{name} done"),
            author: name,
            branch: ctx.branch
          )
        ]
      end
    })
  end

  test "two sub-agents both produce events" do
    sub1 = make_agent("alpha")
    sub2 = make_agent("beta")
    par = %ParallelAgent{name: "par", sub_agents: [sub1, sub2]}

    events = par |> ParallelAgent.run(make_ctx()) |> Enum.to_list()
    assert length(events) == 2

    authors = events |> Enum.map(& &1.author) |> Enum.sort()
    assert authors == ["alpha", "beta"]
  end

  test "branch names are correct" do
    sub1 = make_agent("s1")
    sub2 = make_agent("s2")
    par = %ParallelAgent{name: "par", sub_agents: [sub1, sub2]}

    events = par |> ParallelAgent.run(make_ctx()) |> Enum.to_list()
    branches = events |> Enum.map(& &1.branch) |> Enum.sort()
    assert branches == ["par.s1", "par.s2"]
  end

  test "three sub-agents all produce events" do
    sub1 = make_agent("x")
    sub2 = make_agent("y")
    sub3 = make_agent("z")
    par = %ParallelAgent{name: "par", sub_agents: [sub1, sub2, sub3]}

    events = par |> ParallelAgent.run(make_ctx()) |> Enum.to_list()
    assert length(events) == 3

    authors = events |> Enum.map(& &1.author) |> Enum.sort()
    assert authors == ["x", "y", "z"]
  end

  test "nested branch naming" do
    inner_sub = make_agent("leaf")
    inner_par = %ParallelAgent{name: "inner", sub_agents: [inner_sub]}

    # Wrap inner in a custom agent that delegates
    outer_sub =
      CustomAgent.new(%Config{
        name: "inner",
        run: fn ctx ->
          ParallelAgent.run(inner_par, ctx) |> Enum.to_list()
        end
      })

    outer = %ParallelAgent{name: "outer", sub_agents: [outer_sub]}
    events = outer |> ParallelAgent.run(make_ctx()) |> Enum.to_list()
    assert length(events) == 1

    # Branch should be outer.inner for the custom wrapper, then inner.leaf inside
    [event] = events
    assert event.branch == "outer.inner.inner.leaf"
  end

  test "name/1, description/1, sub_agents/1" do
    sub = make_agent("child")

    par = %ParallelAgent{
      name: "my-par",
      description: "Parallel exec",
      sub_agents: [sub]
    }

    assert ParallelAgent.name(par) == "my-par"
    assert ParallelAgent.description(par) == "Parallel exec"
    assert ParallelAgent.sub_agents(par) == [sub]
  end
end
