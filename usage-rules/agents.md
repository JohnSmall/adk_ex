# ADK Ex: Agents

## Agent Types

### LlmAgent — LLM-powered agent with tools

The primary agent type. Sends messages to an LLM, executes tool calls, and streams events.

```elixir
%ADK.Agent.LlmAgent{
  name: "research-agent",
  model: ADK.Model.Registry.resolve("gemini-2.0-flash"),
  instruction: "You are a research assistant.",
  tools: [search_tool, summarize_tool],
  sub_agents: [detail_agent],
  output_key: nil,          # set to store final output in state
  output_schema: nil,       # JSON schema to constrain output
  include_contents: :default,
  disallow_transfer_to_parent: false,
  disallow_transfer_to_peers: false
}
```

Key callback fields (all lists of functions):
- `before_agent_callbacks`, `after_agent_callbacks`
- `before_model_callbacks`, `after_model_callbacks`, `on_model_error_callbacks`
- `before_tool_callbacks`, `after_tool_callbacks`, `on_tool_error_callbacks`

### LoopAgent — iterate sub-agents

Runs sub-agents in sequence repeatedly until `max_iterations` is reached or an agent escalates.

```elixir
%ADK.Agent.LoopAgent{
  name: "retry-loop",
  sub_agents: [check_agent, fix_agent],
  max_iterations: 5   # 0 = infinite
}
```

### SequentialAgent — run sub-agents once in order

Delegates to LoopAgent with `max_iterations: 1`. Use when you need a pipeline of agents.

```elixir
%ADK.Agent.SequentialAgent{
  name: "pipeline",
  sub_agents: [extract_agent, transform_agent, load_agent]
}
```

### ParallelAgent — run sub-agents concurrently

Spawns each sub-agent as a Task. Each runs on an isolated branch (`"parent.sub"`). Results merge after all complete.

```elixir
%ADK.Agent.ParallelAgent{
  name: "fan-out",
  sub_agents: [api_agent, db_agent, cache_agent]
}
```

### CustomAgent — arbitrary run logic

Wraps a function as an agent.

```elixir
config = %ADK.Agent.Config{
  name: "custom",
  description: "Does custom work",
  sub_agents: [],
  run: fn agent, ctx ->
    event = %ADK.Event{
      author: agent.config.name,
      content: ADK.Types.Content.new_from_text("model", "Done")
    }
    {:ok, [event]}
  end
}

agent = ADK.Agent.CustomAgent.new(config)
```

## When to Use Each Agent

| Need | Agent |
|------|-------|
| Call an LLM with tools | `LlmAgent` |
| Run agents A, B, C in order once | `SequentialAgent` |
| Retry a workflow up to N times | `LoopAgent` |
| Fan out work in parallel | `ParallelAgent` |
| Custom logic, no LLM | `CustomAgent` |

## Agent Transfer

An LlmAgent can transfer control to a sub-agent or peer via `ADK.Tool.TransferToAgent`. The Flow automatically injects this tool when sub-agents exist.

The LLM calls the tool with `{"agent_name": "target-agent"}` and the framework handles the transfer. The target agent must be a sub-agent of the current agent, a peer (sibling sub-agent under the same parent), or the parent (unless `disallow_transfer_to_parent: true`).

## Sub-agents

Sub-agents are set via the `sub_agents` field on any agent struct. The agent tree is validated at runner creation — all agent names must be unique within the tree.

```elixir
root = %ADK.Agent.LlmAgent{
  name: "root",
  model: model,
  sub_agents: [
    %ADK.Agent.LlmAgent{name: "helper-a", model: model},
    %ADK.Agent.LlmAgent{name: "helper-b", model: model}
  ]
}
```

## Rules

1. All agent names must be unique within the agent tree.
2. `ADK.Agent` is a behaviour — never call `ADK.Agent.run/2`. Call `agent.__struct__.run(agent, ctx)` or use the concrete module directly.
3. SequentialAgent is syntactic sugar for LoopAgent — don't use LoopAgent with `max_iterations: 1`.
4. ParallelAgent branches are isolated — state changes in one branch don't affect others until merge.
