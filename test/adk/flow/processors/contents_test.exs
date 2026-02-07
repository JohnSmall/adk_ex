defmodule ADK.Flow.Processors.ContentsTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.InvocationContext
  alias ADK.Event
  alias ADK.Flow.Processors.Contents
  alias ADK.Model.LlmRequest
  alias ADK.Session
  alias ADK.Types.Content

  defmodule FakeAgent do
    defstruct name: "test-agent", include_contents: :default
    def name(%__MODULE__{name: n}), do: n
    def description(_), do: ""
  end

  defp make_ctx(events, opts \\ []) do
    agent_name = Keyword.get(opts, :agent_name, "test-agent")
    include = Keyword.get(opts, :include_contents, :default)
    branch = Keyword.get(opts, :branch, nil)

    agent = %FakeAgent{name: agent_name, include_contents: include}
    session = %Session{id: "s1", app_name: "test", user_id: "u1", events: events}
    %InvocationContext{agent: agent, session: session, branch: branch}
  end

  test "empty session produces empty contents" do
    ctx = make_ctx([])
    {:ok, request} = Contents.process(ctx, %LlmRequest{}, %{})
    assert request.contents == []
  end

  test "user and model events are preserved" do
    events = [
      Event.new(author: "user", content: Content.new_from_text("user", "Hello")),
      Event.new(author: "test-agent", content: Content.new_from_text("model", "Hi there!"))
    ]

    ctx = make_ctx(events)
    {:ok, request} = Contents.process(ctx, %LlmRequest{}, %{})
    assert length(request.contents) == 2
    assert hd(request.contents).role == "user"
    assert List.last(request.contents).role == "model"
  end

  test "partial events are excluded" do
    events = [
      Event.new(author: "user", content: Content.new_from_text("user", "Hello")),
      Event.new(author: "test-agent", content: Content.new_from_text("model", "partial"), partial: true),
      Event.new(author: "test-agent", content: Content.new_from_text("model", "Full response"))
    ]

    ctx = make_ctx(events)
    {:ok, request} = Contents.process(ctx, %LlmRequest{}, %{})
    assert length(request.contents) == 2
  end

  test "events without content are excluded" do
    events = [
      Event.new(author: "user", content: Content.new_from_text("user", "Hello")),
      Event.new(author: "test-agent", content: nil)
    ]

    ctx = make_ctx(events)
    {:ok, request} = Contents.process(ctx, %LlmRequest{}, %{})
    assert length(request.contents) == 1
  end

  test "include_contents :none produces empty" do
    events = [
      Event.new(author: "user", content: Content.new_from_text("user", "Hello"))
    ]

    ctx = make_ctx(events, include_contents: :none)
    {:ok, request} = Contents.process(ctx, %LlmRequest{}, %{})
    assert request.contents == []
  end

  test "foreign agent model content is converted to user role" do
    events = [
      Event.new(author: "other-agent", content: Content.new_from_text("model", "I am other agent"))
    ]

    ctx = make_ctx(events, agent_name: "my-agent")
    {:ok, request} = Contents.process(ctx, %LlmRequest{}, %{})
    assert length(request.contents) == 1
    assert hd(request.contents).role == "user"
    assert hd(hd(request.contents).parts).text =~ "[other-agent]"
  end

  test "branch filtering" do
    events = [
      Event.new(author: "user", content: Content.new_from_text("user", "Hello"), branch: nil),
      Event.new(
        author: "test-agent",
        content: Content.new_from_text("model", "On branch A"),
        branch: "branch-a"
      ),
      Event.new(
        author: "test-agent",
        content: Content.new_from_text("model", "On branch B"),
        branch: "branch-b"
      )
    ]

    # When on branch-a, should see nil-branch + branch-a events
    ctx = make_ctx(events, branch: "branch-a")
    {:ok, request} = Contents.process(ctx, %LlmRequest{}, %{})

    texts =
      Enum.flat_map(request.contents, fn c ->
        Enum.map(c.parts, fn p -> p.text end)
      end)

    assert "Hello" in texts
    assert "On branch A" in texts
    refute "On branch B" in texts
  end
end
