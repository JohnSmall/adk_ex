# Architecture Document: Elixir ADK

## Document Info
- **Project**: Elixir ADK
- **Version**: 0.5.0
- **Date**: 2026-02-08
- **Status**: Phases 1-5 Complete (240 tests adk_ex + 21 tests adk_ex_ecto)

---

## 1. Execution Model

The ADK is an event-sourced agent framework. All agent execution produces a stream of Events:

```
User Message
     |
     v
ADK.Runner.run/5
     |
     +--> Get/create session from SessionService (via runner.session_module)
     +--> [plugin: on_user_message] (may modify user content)
     +--> Append user message event
     +--> [plugin: before_run] (may short-circuit entire run)
     +--> Find agent to run (history scan or root)
     |
     +--> ADK.Agent.LlmAgent.run/2
     |         |
     |         +--> [plugin: before_agent] (may short-circuit)
     |         +--> [before_agent_callbacks] (may short-circuit)
     |         |
     |         +--> ADK.Flow.run/2 (Stream.resource/3 loop)
     |         |         |
     |         |         +--> Resolve toolsets (dynamic tool providers)
     |         |         +--> Build LlmRequest via 5 processors:
     |         |         |       Basic -> ToolProcessor -> Instructions -> AgentTransfer -> Contents
     |         |         |
     |         |         +--> [plugin: before_model] (may short-circuit)
     |         |         +--> [before_model_callbacks] (may short-circuit)
     |         |         +--> Model.generate_content/3 (Gemini/Claude/Mock)
     |         |         +--> [plugin: after_model] (may replace)
     |         |         +--> [after_model_callbacks] (may replace)
     |         |         |
     |         |         +--> If function_calls in response:
     |         |         |       [plugin: before_tool] -> [before_tool_callbacks]
     |         |         |       -> Tool.run/3
     |         |         |       -> [plugin: after_tool] -> [after_tool_callbacks]
     |         |         |       Build tool response event -> loop back to LLM
     |         |         |
     |         |         +--> If text response (final_response?):
     |         |                 Emit event, halt loop
     |         |
     |         +--> [plugin: after_agent] (may short-circuit)
     |         +--> [after_agent_callbacks] (may short-circuit)
     |         +--> If output_key: save text to state_delta
     |
     +--> For each event:
     |       +--> [plugin: on_event] (may modify event)
     |       +--> Commit to SessionService (non-partial only)
     |       +--> Yield to caller
     +--> [plugin: after_run] (notification)
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

  # === Phase 3: Orchestration ===
  agent/
    loop_agent.ex                    # Iterate sub-agents (max_iterations, escalation exit)
    sequential_agent.ex              # LoopAgent wrapper (max_iterations=1)
    parallel_agent.ex                # Task.async + Task.await_many, branch isolation
  tool/
    transfer_to_agent.ex             # Tool signaling agent transfer
  flow/
    processors/
      agent_transfer.ex              # Injects transfer tool + target instructions

  # === Phase 4: Services ===
  memory/
    entry.ex                         # Memory.Entry struct (content, author, timestamp)
    service.ex                       # Memory.Service behaviour (add_session, search)
    in_memory.ex                     # GenServer + ETS, word-based search
  artifact/
    service.ex                       # Artifact.Service behaviour (save, load, delete, list, versions)
    in_memory.ex                     # GenServer + ETS, versioned storage, user-scoped
  tool/
    load_memory.ex                   # LoadMemory tool (searches memory via context)
    load_artifacts.ex                # LoadArtifacts tool (loads artifacts by name)
  telemetry.ex                       # Dual telemetry: OTel spans + :telemetry events

  # === Phase 5: Plugins, Toolsets ===
  plugin.ex                          # Plugin struct (12 callback fields) + new/1
  plugin/
    manager.ex                       # Plugin.Manager — chains plugins, first non-nil wins
  tool/
    toolset.ex                       # Toolset behaviour (name/1, tools/2)
```

### Database Sessions (separate package: `adk_ex_ecto`)

```
/workspace/elixir_code/adk_ex_ecto/
  lib/adk_ex_ecto/
    session_service.ex               # Implements ADK.Session.Service via Ecto
    migration.ex                     # Creates 4 tables with composite PKs
    schemas/
      session.ex                     # adk_sessions table
      event.ex                       # adk_events table
      app_state.ex                   # adk_app_states table
      user_state.ex                  # adk_user_states table
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

### Plugin System (Phase 5)

Plugins hook into the entire agent lifecycle via `ADK.Plugin` structs with 12 callback fields. Plugins are managed by `ADK.Plugin.Manager` and run **before** agent callbacks at every hook point.

**Plugin-specific hooks (Runner level):**

| Hook | Signature | Behavior |
|------|-----------|----------|
| on_user_message | `(InvocationContext, Content -> {Content \| nil, InvocationContext})` | May modify user input |
| before_run | `(InvocationContext -> {Content \| nil, InvocationContext})` | May short-circuit entire run |
| after_run | `(InvocationContext -> :ok)` | Notification only, no short-circuit |
| on_event | `(InvocationContext, Event -> {Event \| nil, InvocationContext})` | May modify each event |

**Agent/Model/Tool hooks** reuse the same callback signatures as agent callbacks (above), but plugins are checked first. If a plugin returns non-nil, agent callbacks are skipped entirely.

### Toolset System (Phase 5)

`ADK.Tool.Toolset` is a behaviour for dynamic tool providers resolved at runtime:

```elixir
@callback name(toolset :: struct()) :: String.t()
@callback tools(toolset :: struct(), ctx :: InvocationContext.t()) :: {:ok, [struct()]} | {:error, term()}
```

Toolsets are resolved in `Flow.run_one_step` before building the LLM request. Errors are logged but don't crash the flow.

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
4. **AgentTransfer** — Injects transfer_to_agent tool + target agent instructions into request
5. **Contents** — Builds conversation history from session events; filters by branch; converts foreign agent content to user perspective

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
| ParallelAgent concurrency | `Task.async` + `Task.await_many` | Branch isolation per sub-agent |
| SequentialAgent reuse | LoopAgent(max_iterations=1) | Matches Go ADK pattern |
| Plugin hooks | `ADK.Plugin` struct + `Manager` | Callbacks before agent callbacks; first non-nil wins |
| Toolsets | `ADK.Tool.Toolset` behaviour | Dynamic tool providers resolved at runtime |
| Session dispatch | `Runner.session_module` field | Pluggable session backends (InMemory, Ecto, custom) |

---

## 9. Memory Service

### Architecture
- **Behaviour**: `ADK.Memory.Service` — `add_session/2`, `search/2`
- **InMemory impl**: GenServer + single ETS table keyed by `{app_name, user_id}`
- **Search**: Word-based intersection — query words matched against precomputed word maps per entry
- **Word maps**: `%{word => true}` (not MapSet — dialyzer rule)

### Integration
- Wired via `InvocationContext.memory_service` (GenServer ref or nil)
- `CallbackContext.search_memory/2` delegates to memory service
- `ToolContext.search_memory/2` delegates through CallbackContext
- `ADK.Tool.LoadMemory` — LLM-callable tool wrapping `search_memory`

---

## 10. Artifact Service

### Architecture
- **Behaviour**: `ADK.Artifact.Service` — save, load, delete, list, versions
- **InMemory impl**: GenServer + ETS keyed by `{app_name, user_id, session_id, filename, version}`
- **Versioning**: Auto-incrementing version on save; load version=0 returns latest
- **User-scoped**: Filenames starting with `"user:"` stored with `session_id = "user"` (shared across sessions)
- **Validation**: Rejects filenames containing `/` or `\`

### Integration
- Wired via `InvocationContext.artifact_service` (GenServer ref or nil)
- `ToolContext.save_artifact/3` — saves + tracks in `actions.artifact_delta`
- `ToolContext.load_artifact/2-3`, `list_artifacts/1`
- `ADK.Tool.LoadArtifacts` — LLM-callable tool wrapping artifact loading

---

## 11. Telemetry

### Dual Emission
`ADK.Telemetry` emits both OpenTelemetry spans and Elixir `:telemetry` events for each instrumented operation.

### Instrumentation Points (in `ADK.Flow`)
1. **LLM call** — `span_llm_call/2` wraps `Model.generate_content/3`
   - OTel span: `"call_llm"` with `gen_ai.*` attributes
   - Telemetry: `[:adk_ex, :llm, :start | :stop | :exception]`
2. **Tool call** — `span_tool_call/2` wraps `Tool.run/3`
   - OTel span: `"execute_tool {name}"` with tool attributes
   - Telemetry: `[:adk_ex, :tool, :start | :stop | :exception]`
3. **Merged tools** — `span_merged_tools/1` after parallel tool execution
   - OTel span: `"execute_tool (merged)"`

### OTel Span Attributes
- LLM: `gen_ai.system`, `gen_ai.request.model`, `gen_ai.operation.name`, `gcp.vertex.agent.invocation_id`, `gcp.vertex.agent.session_id`
- Tool: `gen_ai.operation.name`, `gen_ai.tool.name`, `gen_ai.tool.call.id`

---

## 12. Testing Strategy

### Unit Tests (240 passing in adk_ex, 21 in adk_ex_ecto)
- **Phase 1 (75)**: Types, Event, Session/State/InMemory, Agent/CustomAgent/Tree
- **Phase 2 (63)**: LlmRequest, LlmResponse, Mock, FunctionTool, ToolContext, Instructions processor, Contents processor, Flow (7 tests), LlmAgent (6 tests), Runner (6 tests)
- **Phase 3 (30)**: LoopAgent, SequentialAgent, ParallelAgent, TransferToAgent, AgentTransfer processor, multi-agent integration
- **Phase 4 (49)**: Memory InMemory (10), Artifact InMemory (17), Context helpers (7), LoadMemory (4), LoadArtifacts (4), Telemetry (7)
- **Phase 5 (23 adk_ex + 21 adk_ex_ecto)**: Plugin Manager (18), Toolset (5), SessionService (21 in adk_ex_ecto)

### Integration Tests (4, excluded by default)
- `test/integration/gemini_test.exs` — Requires `GEMINI_API_KEY`
- `test/integration/claude_test.exs` — Requires `ANTHROPIC_API_KEY`
- Run with: `mix test test/integration/ --include integration`

### Quality Gates
- `mix test` — All tests pass
- `mix credo` — No issues
- `mix dialyzer` — 0 errors
