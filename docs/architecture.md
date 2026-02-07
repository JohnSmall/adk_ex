# Architecture Document: Elixir ADK

## Document Info
- **Project**: Elixir ADK
- **Version**: 0.2.0
- **Date**: 2026-02-07
- **Status**: Phase 2 Complete

---

## 1. Execution Model

The ADK is an event-sourced agent framework. All agent execution produces a stream of Events:

```
User Message
     |
     v
ADK.Runner.run/5
     |
     +--> Get/create session from SessionService
     +--> Append user message event
     +--> Find agent to run (history scan or root)
     |
     +--> ADK.Agent.LlmAgent.run/2
     |         |
     |         +--> [before_agent_callbacks] (may short-circuit)
     |         |
     |         +--> ADK.Flow.run/2 (Stream.resource/3 loop)
     |         |         |
     |         |         +--> Build LlmRequest via 4 processors:
     |         |         |       Basic -> ToolProcessor -> Instructions -> Contents
     |         |         |
     |         |         +--> [before_model_callbacks] (may short-circuit)
     |         |         +--> Model.generate_content/3 (Gemini/Claude/Mock)
     |         |         +--> [after_model_callbacks] (may replace)
     |         |         |
     |         |         +--> If function_calls in response:
     |         |         |       [before_tool_callbacks] -> Tool.run/3 -> [after_tool_callbacks]
     |         |         |       Build tool response event -> loop back to LLM
     |         |         |
     |         |         +--> If text response (final_response?):
     |         |                 Emit event, halt loop
     |         |
     |         +--> [after_agent_callbacks] (may short-circuit)
     |         +--> If output_key: save text to state_delta
     |
     +--> For each event:
     |       +--> Commit to SessionService (non-partial only)
     |       +--> Yield to caller
     |
     v
Stream of Events returned to application
```

---

## 2. Module Map (Actual Implementation)

```
lib/adk/
  adk.ex                             # Top-level module
  application.ex                     # OTP application (starts InMemory session)

  # === Phase 1: Foundation ===
  types.ex                           # Blob, FunctionCall, FunctionResponse, Part, Content, Types
  event.ex                           # Event.Actions (defined first), Event
  session.ex                         # Session struct
  session/
    state.ex                         # Prefix-based state scoping (app:, user:, temp:)
    service.ex                       # Session.Service behaviour
    in_memory.ex                     # GenServer + 3 ETS tables
  run_config.ex                      # RunConfig struct
  agent.ex                           # Agent behaviour (name, description, run, sub_agents)
  agent/
    config.ex                        # Agent.Config for CustomAgent
    custom_agent.ex                  # CustomAgent with before/after callbacks
    invocation_context.ex            # InvocationContext (agent, session, services, parent_map, root_agent)
    callback_context.ex              # CallbackContext (wraps InvocationContext + actions)
    tree.ex                          # find_agent/2, build_parent_map/1, validate_unique_names/1

  # === Phase 2: Runner + Tool + LLM Agent ===
  model.ex                           # Model behaviour (name/1, generate_content/3)
  model/
    llm_request.ex                   # LlmRequest struct (model, system_instruction, contents, config, tools)
    llm_response.ex                  # LlmResponse struct (content, partial, turn_complete, error_*, metadata)
    mock.ex                          # Mock model (stateful via Agent process, Mock.new/1)
    gemini.ex                        # Gemini REST provider (Req)
    claude.ex                        # Claude REST provider (Req)
    registry.ex                      # Model name -> provider resolution
  tool.ex                            # Tool behaviour (name, description, declaration, run, long_running?)
  tool/
    context.ex                       # ToolContext (wraps CallbackContext + function_call_id + actions)
    function_tool.ex                 # FunctionTool (anonymous function wrapper, try/rescue)
  flow.ex                            # Flow engine (Stream.resource/3, max 25 iterations)
  flow/
    processors/
      basic.ex                       # Copies generate_content_config into request
      tool_processor.ex              # Populates tools map + function declarations
      instructions.ex                # System instruction + {variable} interpolation
      contents.ex                    # Conversation history from session events
  agent/
    llm_agent.ex                     # LlmAgent (model, tools, instructions, callbacks, output_key)
  runner.ex                          # Runner (session lifecycle, event persistence, agent routing)

  # === Phase 3: Orchestration (NEXT) ===
  # agent/sequential_agent.ex        # Run sub-agents in order
  # agent/parallel_agent.ex          # Run sub-agents concurrently (Task.async_stream)
  # agent/loop_agent.ex              # Repeat until escalation/max_iterations
```

---

## 3. Key Data Structures

### Event
```elixir
%ADK.Event{
  id: "uuid",                        # Auto-generated
  timestamp: ~U[...],                # Auto-generated
  invocation_id: "uuid",             # Groups events in one run
  branch: "branch-name" | nil,       # For parallel agent isolation
  author: "agent-name" | "user",
  content: %Content{role: "model"|"user", parts: [%Part{}]},
  partial: false,                    # Streaming chunk?
  turn_complete: true,               # Final chunk?
  error_code: nil,                   # Error identifier
  error_message: nil,                # Error description
  actions: %Actions{                 # Side effects
    state_delta: %{},                # State changes to commit
    artifact_delta: %{},             # Artifact changes
    transfer_to_agent: nil,          # Agent transfer target
    escalate: false,                 # Escalation flag
    skip_summarization: false        # Skip summarization flag
  }
}
```

### LlmRequest
```elixir
%ADK.Model.LlmRequest{
  model: "gemini-2.0-flash",         # Model name string
  system_instruction: %Content{},    # System prompt
  contents: [%Content{}],            # Conversation history
  config: %{                         # Provider-specific settings
    "temperature" => 0.7,
    "tools" => [%{"function_declarations" => [...]}]
  },
  tools: %{"tool_name" => %FunctionTool{}}  # O(1) lookup map
}
```

### Flow State Machine
```
:step (iteration 0) -> run_one_step -> events
  |-> last event is final_response? -> :done (halt)
  |-> last event has function calls -> :step (iteration + 1)
  |-> iteration >= 25 -> error event, :done
```

---

## 4. Callback System

All callbacks follow the same pattern: `{value | nil, updated_context}`.

| Hook | Signature | Short-circuit |
|------|-----------|---------------|
| before_agent | `(CallbackContext -> {Content \| nil, CallbackContext})` | Non-nil Content skips agent |
| after_agent | `(CallbackContext -> {Content \| nil, CallbackContext})` | Non-nil Content replaces output |
| before_model | `(CallbackContext, LlmRequest -> {LlmResponse \| nil, CallbackContext})` | Non-nil LlmResponse skips LLM |
| after_model | `(CallbackContext, LlmResponse -> {LlmResponse \| nil, CallbackContext})` | Non-nil LlmResponse replaces |
| before_tool | `(ToolContext, tool, args -> {map \| nil, ToolContext})` | Non-nil map skips tool |
| after_tool | `(ToolContext, tool, args, result -> {map \| nil, ToolContext})` | Non-nil map replaces result |

Multiple callbacks of same type are chained; first non-nil return wins.

---

## 5. State System

### Prefix Scoping
| Prefix | Scope | Storage | Persisted? |
|--------|-------|---------|------------|
| (none) | Session-local | sessions ETS | Yes |
| `app:` | All users/sessions | app_state ETS | Yes |
| `user:` | User's sessions | user_state ETS | Yes |
| `temp:` | Current invocation | Not stored | No |

### State Delegation Chain (reads)
```
ToolContext.get_state(key)
  -> check tool.actions.state_delta
  -> check callback_context.actions.state_delta
  -> check session.state
```

### State Commit (writes)
State changes flow through `event.actions.state_delta` and are committed atomically by `Session.InMemory.append_event/3`. The session service extracts app:/user:/session deltas and routes them to appropriate ETS tables.

---

## 6. Request Processor Pipeline

Each processor is a function `(InvocationContext, LlmRequest, flow_state) -> {:ok, LlmRequest}`:

1. **Basic** — Copies `agent.generate_content_config` into `request.config`
2. **ToolProcessor** — Builds `request.tools` map and adds function declarations to config
3. **Instructions** — Builds `system_instruction` from global + agent instruction; interpolates `{var}` from session state
4. **Contents** — Builds conversation history from session events; filters by branch; converts foreign agent content to user perspective

---

## 7. Model Providers

### Gemini (`ADK.Model.Gemini`)
- POST to `{base_url}/models/{name}:generateContent?key={key}`
- Serializes ADK Content/Part to Gemini format (functionCall, functionResponse, text, inlineData)
- Parses response candidates into LlmResponse

### Claude (`ADK.Model.Claude`)
- POST to `{base_url}/messages` with `x-api-key` header
- Converts ADK types to Claude format (tool_use/tool_result content blocks)
- System instruction as top-level `system` field (not in messages)

### Mock (`ADK.Model.Mock`)
- `Mock.new(responses: [...])` starts an Agent process
- `generate_content/3` pops responses sequentially via `Agent.get_and_update`
- Falls back to "Mock response" when list exhausted
- Critical for testing: without the Agent process, the same response would repeat infinitely in the Flow loop

---

## 8. Elixir/OTP Mapping

| ADK Concept | Elixir Implementation | Notes |
|-------------|----------------------|-------|
| BaseAgent | `@behaviour ADK.Agent` + struct | Callbacks: name/1, description/1, run/2, sub_agents/1 |
| Agent.Run() stream | `Stream.resource/3` | Lazy enumerable with :before/:flow/:after state machine |
| Runner event loop | `Stream.resource/3` + init_run | Eagerly collects agent events, yields with session commits |
| Session storage | GenServer + 3 ETS tables | Writes serialized, reads concurrent |
| InvocationContext | Struct with all services | Threaded through agent tree |
| Async generators | `Enumerable.t()` (Stream) | Flow.run returns Stream of Events |
| Pydantic models | `defstruct` + `@type` | Plus `@enforce_keys` for required fields |
| Tool execution | `tool.__struct__.run(tool, ctx, args)` | Dynamic dispatch via struct module |
| Model execution | `model.__struct__.generate_content(model, req, stream)` | Same pattern |
| Parallel agents (Phase 3) | `Task.async_stream` | With branch isolation per sub-agent |

---

## 9. Testing Strategy

### Unit Tests (138 passing)
- **Phase 1 (75)**: Types, Event, Session/State/InMemory, Agent/CustomAgent/Tree
- **Phase 2 (63)**: LlmRequest, LlmResponse, Mock, FunctionTool, ToolContext, Instructions processor, Contents processor, Flow (7 tests), LlmAgent (6 tests), Runner (6 tests)

### Integration Tests (4, excluded by default)
- `test/integration/gemini_test.exs` — Requires `GEMINI_API_KEY`
- `test/integration/claude_test.exs` — Requires `ANTHROPIC_API_KEY`
- Run with: `mix test test/integration/ --include integration`

### Quality Gates
- `mix test` — All tests pass
- `mix credo` — No issues
- `mix dialyzer` — 0 errors
