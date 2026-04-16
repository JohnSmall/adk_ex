# ADK Ex: Tools

## FunctionTool

The primary way to define tools. Use `handler:`, never `function:`.

```elixir
tool = ADK.Tool.FunctionTool.new(
  name: "search_docs",
  description: "Search documentation by query",
  handler: fn ctx, %{"query" => query} ->
    results = MyApp.Search.run(query)
    {:ok, %{"results" => results}}
  end,
  parameters: %{
    "type" => "object",
    "properties" => %{
      "query" => %{"type" => "string", "description" => "Search query"}
    },
    "required" => ["query"]
  }
)
```

### Handler Signature

```elixir
(ADK.Tool.Context.t(), map()) -> {:ok, map()} | {:error, term()}
```

- First argument: `ADK.Tool.Context` with session state, agent info, services
- Second argument: parsed JSON arguments from the LLM as a map
- Return `{:ok, result_map}` on success or `{:error, reason}` on failure

### FunctionTool Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `String.t()` | required | Tool name exposed to the LLM |
| `description` | `String.t()` | required | Tool description for the LLM |
| `handler` | `function/2` | required | The function to execute |
| `parameters` | `map()` | `%{}` | JSON Schema for arguments |
| `is_long_running` | `boolean()` | `false` | Hint for timeout handling |

## Tool.Context

Available inside tool handlers:

```elixir
%ADK.Tool.Context{
  state: %{},              # current session state
  agent_name: "my-agent",
  function_call_id: "...",
  actions: %ADK.Event.Actions{},
  session: %ADK.Session{},
  artifact_service: nil,
  memory_service: nil
}
```

To modify state from a tool, update `ctx.actions.state_delta`:

```elixir
handler: fn ctx, args ->
  updated_actions = %{ctx.actions | state_delta: Map.put(ctx.actions.state_delta, "result", "value")}
  updated_ctx = %{ctx | actions: updated_actions}
  {:ok, %{"status" => "done"}}
end
```

## Built-in Tools

### TransferToAgent

Automatically injected when an LlmAgent has sub-agents. The LLM calls it with `{"agent_name": "target"}` to transfer control. You don't need to add it manually.

### LoadMemory

Searches the memory service for relevant entries.

```elixir
tool = %ADK.Tool.LoadMemory{}
# Add to agent's tools list — requires memory_service on the Runner
```

### LoadArtifacts

Loads artifacts by name from the artifact service.

```elixir
tool = %ADK.Tool.LoadArtifacts{}
# Add to agent's tools list — requires artifact_service on the Runner
```

## Toolset Behaviour

For dynamic tool sets that depend on runtime context, implement the `ADK.Tool.Toolset` behaviour:

```elixir
defmodule MyApp.DynamicTools do
  @behaviour ADK.Tool.Toolset

  @impl true
  def name(_toolset), do: "dynamic-tools"

  @impl true
  def tools(_toolset, ctx) do
    tools = case ctx.state["mode"] do
      "admin" -> [admin_tool(), user_tool()]
      _ -> [user_tool()]
    end
    {:ok, tools}
  end
end
```

Add to an agent via the `toolsets` field:

```elixir
%ADK.Agent.LlmAgent{
  name: "agent",
  model: model,
  toolsets: [%MyApp.DynamicTools{}]
}
```

Toolsets are resolved at each flow iteration — tools can change between LLM calls.

## Rules

1. **Always use `handler:` not `function:`** when creating FunctionTool.
2. Tool handlers receive parsed JSON args as a map — match on string keys, not atoms.
3. Parameters follow JSON Schema format. Omit `parameters` for tools that take no arguments.
4. TransferToAgent is auto-injected — don't add it to the tools list manually.
5. Toolset `tools/2` is called on every flow iteration, so keep it fast.
