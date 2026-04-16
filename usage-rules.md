# ADK Ex Usage Rules

`adk_ex` is an Elixir port of Google's Agent Development Kit (ADK). It provides agent orchestration, session management, tool use, LLM abstraction, plugins, and telemetry. It is transport-agnostic — no HTTP/Plug dependencies.

## Architecture

```
User Message -> Runner -> Agent -> Flow -> LLM
                  |          |        |       |
              [plugins]  [plugins] [processors]|
                  |          |     [tool call loop]
                  |          |     [agent transfer]
                  |          |        |
               [commits events + state to Session]
                  |
               [yields Events as a stream]
```

## Core Patterns

### Creating an Agent

```elixir
agent = %ADK.Agent.LlmAgent{
  name: "my-agent",
  model: ADK.Model.Registry.resolve("gemini-2.0-flash"),
  instruction: "You are a helpful assistant.",
  tools: [my_tool],
  sub_agents: []
}
```

### Defining a Tool

Always use `handler:`, never `function:`.

```elixir
tool = ADK.Tool.FunctionTool.new(
  name: "get_weather",
  description: "Get weather for a city",
  handler: fn _ctx, %{"city" => city} ->
    {:ok, %{"weather" => "Sunny in #{city}"}}
  end
)
```

The handler signature is `(ADK.Tool.Context.t(), map()) -> {:ok, map()} | {:error, term()}`.

### Running an Agent

`ADK.Runner.run/4` returns a stream of `ADK.Event` structs.

```elixir
{:ok, runner} = ADK.Runner.new(
  app_name: "my-app",
  root_agent: agent,
  session_service: session_service
)

events =
  runner
  |> ADK.Runner.run("user-1", "session-1", content)
  |> Enum.to_list()
```

### Session Service

Start the built-in ETS-backed service:

```elixir
{:ok, service} = ADK.Session.InMemory.start_link(name: :my_sessions)

{:ok, session} = ADK.Session.InMemory.create(service,
  app_name: "my-app",
  user_id: "user-1",
  session_id: "session-1",
  state: %{}
)
```

For database-backed sessions, use the separate `adk_ex_ecto` package.

### State Prefixes

Session state keys use prefixes to control scope:

| Prefix | Scope | Persisted? |
|--------|-------|-----------|
| (none) | Session-local | Yes |
| `app:` | Cross-session for the app | Yes |
| `user:` | Cross-session for the user | Yes |
| `temp:` | Current invocation only | No |

### Creating Content

```elixir
content = ADK.Types.Content.new_from_text("user", "Hello, agent!")
```

## Critical Rules

1. **FunctionTool uses `handler:` not `function:`** — `FunctionTool.new(handler: fn/2)`.
2. **Mock model needs `Mock.new/1`** — use `ADK.Model.Mock.new(responses: [...])`, never bare `%ADK.Model.Mock{}`. It starts an Agent process for response sequencing.
3. **Agent behaviour has no module functions** — call `agent.__struct__.run(agent, ctx)` or the implementing module directly. `ADK.Agent` is a behaviour, not a dispatcher.
4. **Telemetry prefix is `[:adk_ex, ...]`** — not `[:adk, ...]`. Events: `[:adk_ex, :llm, :start|:stop]`, `[:adk_ex, :tool, :start|:stop]`.
5. **Model.Registry.resolve/1** — pattern-matches on name: `"gemini-*"` -> Gemini, `"claude-*"` -> Claude.
6. **Plugin callbacks return `{value | nil, updated_context}`** — nil means continue to next plugin; non-nil short-circuits.
7. **All Plugin.Manager.run_* functions accept `nil`** as first arg (no-op) — no nil checks needed at call sites.
8. **Nested module compile order** — define referenced modules before parent modules in the same file (e.g. `Event.Actions` before `Event`).
9. **Avoid MapSet with dialyzer** — use `%{key => true}` maps + `Map.has_key?/2` instead.

## Sub-rules

For detailed guidance on specific topics, see the `usage-rules/` directory:

- `adk_ex:agents` — Agent types, when to use each, sub-agents, agent transfer
- `adk_ex:tools` — FunctionTool, argument schemas, Tool.Context, Toolset behaviour
- `adk_ex:sessions` — Session struct, state prefixes, Service behaviour, switching backends
- `adk_ex:plugins` — Plugin struct, 12 callback hooks, execution order, short-circuit semantics
- `adk_ex:telemetry` — Event naming, OTel span conventions, testing with otel_simple_processor
