# Implementation Plan: Elixir ADK

## Document Info
- **Project**: Elixir ADK
- **Version**: 0.5.0
- **Date**: 2026-02-08

---

## Overview

The implementation is organized into 5 phases, each building on the previous. Each phase produces a working, testable subset of functionality. (A2A protocol is a separate package: `a2a_ex`.)

---

## Phase 1: Foundation (Core Primitives) -- COMPLETE

**Goal**: Establish the project structure, type system, and core data structures.

### Tasks

- [x] **1.1** Create Mix project at `/workspace/elixir_code/adk_ex` with `--sup`
  - Configured mix.exs with deps: jason, elixir_uuid, ex_doc, dialyxir, credo
- [x] **1.2** Define core type structs (`lib/adk/types.ex`)
  - `ADK.Types.Content`, `Part`, `FunctionCall`, `FunctionResponse`, `Blob`
  - Helper functions: `function_calls/1`, `has_function_calls?/1`, etc.
- [x] **1.3** Define Event structs (`lib/adk/event.ex`)
  - `ADK.Event.Actions` (defined first for compile order)
  - `ADK.Event` with `new/1` and `final_response?/1`
- [x] **1.4** Define Session structs
  - `ADK.Session` struct (`lib/adk/session.ex`)
  - `ADK.Session.State` prefix utilities (`lib/adk/session/state.ex`)
  - `ADK.Session.Service` behaviour (`lib/adk/session/service.ex`)
- [x] **1.5** Implement InMemorySessionService (`lib/adk/session/in_memory.ex`)
  - GenServer with 3 ETS tables (sessions, app_state, user_state)
  - Full prefix-based state routing
- [x] **1.6** Define RunConfig struct (`lib/adk/run_config.ex`)
- [x] **1.7** Define Agent behaviour (`lib/adk/agent.ex`)
  - Callbacks: name/1, description/1, run/2, sub_agents/1
- [x] **1.8** Define InvocationContext + CallbackContext
- [x] **1.9** Implement CustomAgent (`lib/adk/agent/custom_agent.ex`)
  - Config struct, before/after callback short-circuiting, author auto-set
- [x] **1.10** Implement Agent tree utilities (`lib/adk/agent/tree.ex`)
  - find_agent/2, build_parent_map/1, validate_unique_names/1

### Verification (all passing)
- 75 tests, 0 failures
- Credo: no issues
- Dialyzer: 0 errors

---

## Phase 2: Runner + Tool System + LLM Agent -- COMPLETE

**Goal**: Build the Runner orchestrator, tool abstraction, and LLM agent so we can execute real agent turns.

**Dependencies**: Phase 1

### Tasks

- [x] **2.1** Define Tool base behaviour (`lib/adk/tool.ex`)
  - Callbacks: name/1, description/1, declaration/1, run/3, long_running?/1
- [x] **2.2** Define ToolContext struct (`lib/adk/tool/context.ex`)
  - Wraps CallbackContext + function_call_id + own Actions
  - get_state/set_state delegation chain: tool → callback → session
- [x] **2.3** Implement FunctionTool (`lib/adk/tool/function_tool.ex`)
  - Wraps anonymous functions as tools with try/rescue error handling
- [x] **2.4** Implement LLM base behaviour (`lib/adk/model.ex`)
  - `@callback generate_content(model, request, stream) :: Enumerable.t()`
  - LlmRequest struct (`lib/adk/model/llm_request.ex`)
  - LlmResponse struct (`lib/adk/model/llm_response.ex`)
  - Mock model (`lib/adk/model/mock.ex`) — stateful via Agent process
- [x] **2.5** Implement Gemini provider (`lib/adk/model/gemini.ex`)
  - REST API calls via Req to generativelanguage.googleapis.com
  - Request/response serialization (Contents, FunctionCall, FunctionResponse)
- [x] **2.6** Implement Claude provider (`lib/adk/model/claude.ex`)
  - REST API calls via Req to api.anthropic.com
  - ADK types ↔ Claude format conversion (tool_use/tool_result blocks)
- [x] **2.7** Implement Model Registry (`lib/adk/model/registry.ex`)
  - Pattern matching: gemini-* → Gemini, claude-* → Claude
- [x] **2.8** Implement Flow engine (`lib/adk/flow.ex`)
  - Stream.resource/3 state machine with max 25 iterations
  - 4 request processors: Basic, ToolProcessor, Instructions, Contents
  - 6 callback hooks: before/after model, before/after tool, tool error
  - Tool execution with error recovery and action merging
- [x] **2.9** Implement LLM Agent (`lib/adk/agent/llm_agent.ex`)
  - before/after agent callbacks, instruction providers, output_key
  - Builds Flow from agent config, delegates to Flow.run/2
- [x] **2.10** Implement Runner (`lib/adk/runner.ex`)
  - `run/5` returning Stream of Events
  - Session auto-creation, event persistence
  - find_agent_to_run via function response matching / history scan
- [x] **2.11** Added InvocationContext fields: parent_map, root_agent

### Verification (all passing)
- 138 tests, 0 failures (75 Phase 1 + 63 Phase 2)
- 4 integration tests (Gemini + Claude, excluded by default)
- Credo: no issues
- Dialyzer: 0 errors

---

## Phase 3: Orchestration Agents + Agent Transfer -- COMPLETE

**Goal**: Implement Sequential, Parallel, and Loop workflow agents, plus agent transfer.

**Dependencies**: Phase 2

### Tasks

- [x] **3.1** Implement LoopAgent (`lib/adk/agent/loop_agent.ex`)
  - Stream.resource + reduce_while, max_iterations, escalation-based termination
  - State propagation between iterations
- [x] **3.2** Implement SequentialAgent (`lib/adk/agent/sequential_agent.ex`)
  - Thin LoopAgent wrapper with max_iterations=1 (matches Go ADK pattern)
- [x] **3.3** Implement ParallelAgent (`lib/adk/agent/parallel_agent.ex`)
  - Task.async + Task.await_many with branch isolation per sub-agent
- [x] **3.4** Implement TransferToAgent tool (`lib/adk/tool/transfer_to_agent.ex`)
  - Tool returning `%{"transfer_to_agent" => name}` in result
- [x] **3.5** Implement AgentTransfer processor (`lib/adk/flow/processors/agent_transfer.ex`)
  - Injects transfer tool into LlmRequest + target agent instructions
  - maybe_set_transfer detects transfer result, maybe_run_transfer executes target agent
- [x] **3.6** Integration tests for multi-agent workflows

### Verification (all passing)
- 168 tests, 0 failures (75 Phase 1 + 63 Phase 2 + 30 Phase 3)
- 4 integration tests (Gemini + Claude, excluded by default)
- Credo: no issues
- Dialyzer: 0 errors

---

## Phase 4: Memory, Artifacts, and Telemetry -- COMPLETE

**Goal**: Memory service, artifact service, and OpenTelemetry-based observability.

**Dependencies**: Phase 3

**Note**: A2A protocol implementation has been extracted to a separate package at `/workspace/elixir_code/a2a_ex/` (github.com/JohnSmall/a2a_ex).

### Tasks

- [x] **4.1** Implement Memory service behaviour + InMemory implementation
  - `ADK.Memory.Entry` — Entry struct (content, author, timestamp)
  - `ADK.Memory.Service` — Behaviour: add_session/2, search/2
  - `ADK.Memory.InMemory` — GenServer + ETS, word-based search
- [x] **4.2** Implement Artifact service behaviour + InMemory implementation
  - `ADK.Artifact.Service` — Behaviour: save, load, delete, list, versions
  - `ADK.Artifact.InMemory` — GenServer + ETS, versioned storage, user-scoped artifacts
- [x] **4.3** Wire services into contexts + add helper methods
  - Updated `InvocationContext` and `Runner` types: `term()` → `GenServer.server() | nil`
  - `CallbackContext.search_memory/2` — delegates to memory service
  - `ToolContext.search_memory/2`, `save_artifact/3`, `load_artifact/2-3`, `list_artifacts/1`
  - `save_artifact` tracks changes in `actions.artifact_delta`
- [x] **4.4** Implement LoadMemory + LoadArtifacts tools
  - `ADK.Tool.LoadMemory` — searches memory via context, returns formatted results
  - `ADK.Tool.LoadArtifacts` — loads artifacts by name, returns content
- [x] **4.5** Implement Telemetry (OpenTelemetry spans + Elixir :telemetry events)
  - `ADK.Telemetry` — dual emission: OTel spans + :telemetry events
  - Instrumented `ADK.Flow`: model calls, tool calls, merged tools
  - Added deps: `opentelemetry_api ~> 1.4`, `opentelemetry ~> 1.5`, `telemetry ~> 1.3`

### Verification (all passing)
- 217 tests, 0 failures (168 Phase 1-3 + 49 Phase 4)
- 4 integration tests (Gemini + Claude, excluded by default)
- Credo: no issues
- Dialyzer: 0 errors

---

## Phase 5: Plugins, Toolsets, and Database Sessions -- COMPLETE

**Goal**: Plugin system, toolset behaviour, and persistent session storage.

**Dependencies**: Phase 4

### Tasks

- [x] **5.1** Implement Plugin system (`ADK.Plugin` struct + `ADK.Plugin.Manager`)
  - Plugin struct with 12 callback fields (on_user_message, on_event, before/after_run, before/after_agent, before/after_model, on_model_error, before/after_tool, on_tool_error)
  - Manager chains plugins in order, first non-nil wins (short-circuit)
  - All `run_*` functions accept `nil` as first arg (no-op when no plugin manager)
  - Plugin name uniqueness validation
- [x] **5.2** Integrate plugins into Runner, Flow, and LlmAgent
  - Runner: `plugins` field, creates Manager, calls on_user_message, before/after_run, on_event
  - Flow: Plugin before/after_model, before/after_tool, on_model_error, on_tool_error
  - LlmAgent: Plugin before/after_agent (checked before agent callbacks)
  - InvocationContext: Added `plugin_manager` field
  - Pattern: Plugins always run first; if plugin short-circuits, agent callbacks are skipped
- [x] **5.3** Implement Toolset behaviour (`ADK.Tool.Toolset`)
  - Behaviour with `name/1` and `tools/2` callbacks
  - LlmAgent: Added `toolsets` field, passes to Flow
  - Flow: Resolves toolsets in `run_one_step` before building request
  - Toolset errors logged but don't crash (return empty list for that toolset)
- [x] **5.4** Add pluggable session dispatch to Runner
  - Runner: Added `session_module` field (default `ADK.Session.InMemory`)
  - All session calls dispatch via `runner.session_module.*` instead of hardcoded InMemory
- [x] **5.5** Implement DatabaseSessionService (`adk_ex_ecto` separate package)
  - New package at `/workspace/elixir_code/adk_ex_ecto/` (github.com/JohnSmall/adk_ex_ecto)
  - `ADKExEcto.SessionService` implements `ADK.Session.Service` via Ecto
  - 4 tables: adk_sessions, adk_events, adk_app_states, adk_user_states
  - `ADKExEcto.Migration` helper for creating tables
  - Ecto schemas for Session, Event, AppState, UserState
  - Full JSON serialization/deserialization for Content, Actions, Parts
  - State prefix routing (app:/user:/temp:/session) matching InMemory behaviour
  - Supports SQLite3 (dev/test) and PostgreSQL (prod)

### Verification (all passing)
- 240 tests, 0 failures (217 Phase 1-4 + 23 Phase 5) in `adk_ex`
- 21 tests, 0 failures in `adk_ex_ecto`
- 4 integration tests (Gemini + Claude, excluded by default)
- Credo: no issues (both packages)
- Dialyzer: 0 errors (both packages)

---

## Dependency Graph

```
Phase 1: Foundation                        <-- COMPLETE
    |
    v
Phase 2: Runner + Tools + LLM Agent       <-- COMPLETE
    |
    v
Phase 3: Orchestration Agents             <-- COMPLETE
    |
    v
Phase 4: Memory, Artifacts, Telemetry     <-- COMPLETE
    |
    v
Phase 5: Plugins, Toolsets, DB Sessions   <-- COMPLETE
```

Note: A2A protocol is a separate package (`a2a_ex`) that depends on this ADK package.

---

## Key Reference Files (Go ADK)

| ADK Component | Go Source File |
|---------------|----------------|
| Agent interface | `/workspace/samples/adk-go/agent/agent.go` |
| Agent contexts | `/workspace/samples/adk-go/agent/context.go` |
| RunConfig | `/workspace/samples/adk-go/agent/run_config.go` |
| Session/Event structs | `/workspace/samples/adk-go/session/session.go` |
| Session service | `/workspace/samples/adk-go/session/service.go` |
| InMemory sessions | `/workspace/samples/adk-go/session/inmemory.go` |
| State utilities | `/workspace/samples/adk-go/internal/sessionutils/utils.go` |
| Runner | `/workspace/samples/adk-go/runner/runner.go` |
| LLM Agent | `/workspace/samples/adk-go/agent/llm_agent.go` |
| Flow | `/workspace/samples/adk-go/agent/flow.go` |
| Tool interface | `/workspace/samples/adk-go/tool/tool.go` |
| Memory service | `/workspace/samples/adk-go/memory/service.go` |
| Artifact service | `/workspace/samples/adk-go/artifact/service.go` |
| Telemetry | `/workspace/samples/adk-go/internal/telemetry/telemetry.go` |
| A2A server | `/workspace/samples/adk-go/server/adka2a/` |
| Plugin struct | `/workspace/samples/adk-go/plugin/plugin.go` |
| Plugin manager | `/workspace/samples/adk-go/internal/plugininternal/plugin_manager.go` |
| Toolset interface | `/workspace/samples/adk-go/tool/tool.go` |
| Database session service | `/workspace/samples/adk-go/session/database/service.go` |
| Database schemas | `/workspace/samples/adk-go/session/database/storage_types.go` |

---

## Key Risks per Phase

| Phase | Risk | Mitigation |
|-------|------|------------|
| 2 | No Elixir GenAI SDK | Use Req + REST API directly; study Go SDK for patterns |
| 2 | SSE parsing complexity | Study Go/Python implementations for chunked response handling |
| 3 | Parallel agent state races | Use ETS with atomic operations; branch isolation |
| 4 | OpenTelemetry dep weight | opentelemetry_api is lightweight; full SDK optional for users |
| 5 | Ecto dependency for DB sessions | Optional dependency; provide behaviour for custom backends |
