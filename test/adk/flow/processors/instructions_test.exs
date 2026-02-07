defmodule ADK.Flow.Processors.InstructionsTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.InvocationContext
  alias ADK.Flow.Processors.Instructions
  alias ADK.Model.LlmRequest
  alias ADK.Session

  defmodule TestAgent do
    defstruct [
      :instruction,
      :global_instruction,
      :instruction_provider,
      :global_instruction_provider,
      name: "fake"
    ]

    def name(%__MODULE__{name: n}), do: n
    def description(_), do: ""
  end

  defp make_ctx(agent_fields, state \\ %{}) do
    agent = struct(TestAgent, agent_fields)
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: state}
    %InvocationContext{agent: agent, session: session}
  end

  test "no instructions produces no system_instruction" do
    ctx = make_ctx(%{instruction: "", global_instruction: ""})
    {:ok, request} = Instructions.process(ctx, %LlmRequest{}, %{})
    assert request.system_instruction == nil
  end

  test "agent instruction is included" do
    ctx = make_ctx(%{instruction: "You are a helpful assistant."})
    {:ok, request} = Instructions.process(ctx, %LlmRequest{}, %{})
    assert hd(request.system_instruction.parts).text == "You are a helpful assistant."
  end

  test "global + agent instructions are combined" do
    ctx = make_ctx(%{global_instruction: "Be concise.", instruction: "You help with code."})
    {:ok, request} = Instructions.process(ctx, %LlmRequest{}, %{})
    text = hd(request.system_instruction.parts).text
    assert text =~ "Be concise."
    assert text =~ "You help with code."
  end

  test "variable interpolation from session state" do
    ctx = make_ctx(%{instruction: "The user's name is {name}."}, %{"name" => "Alice"})
    {:ok, request} = Instructions.process(ctx, %LlmRequest{}, %{})
    assert hd(request.system_instruction.parts).text == "The user's name is Alice."
  end

  test "optional variable removed when not in state" do
    ctx = make_ctx(%{instruction: "Pref: {color?}"})
    {:ok, request} = Instructions.process(ctx, %LlmRequest{}, %{})
    assert hd(request.system_instruction.parts).text == "Pref: "
  end

  test "required variable kept as-is when not in state" do
    ctx = make_ctx(%{instruction: "Value: {missing}"})
    {:ok, request} = Instructions.process(ctx, %LlmRequest{}, %{})
    assert hd(request.system_instruction.parts).text == "Value: {missing}"
  end

  test "instruction_provider function is called" do
    provider = fn _ctx -> "Dynamic instruction" end
    ctx = make_ctx(%{instruction_provider: provider})
    {:ok, request} = Instructions.process(ctx, %LlmRequest{}, %{})
    assert hd(request.system_instruction.parts).text == "Dynamic instruction"
  end
end
