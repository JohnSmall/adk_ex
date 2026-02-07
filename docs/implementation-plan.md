# Implementation Plan: Elixir ADK

## Document Info
- **Project**: Elixir ADK
- **Version**: 0.1.0
- **Date**: 2026-02-07

---

## Overview

The implementation is organized into 6 phases, each building on the previous. Each phase produces a working, testable subset of functionality.

---

## Phase 1: Foundation (Core Primitives) -- COMPLETE

**Goal**: Establish the project structure, type system, and core data structures.

### Tasks

- [x] **1.1** Create Mix project at `/workspace/adk` with `--sup`
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

## Phase 3: Orchestration Agents

**Goal**: Implement Sequential, Parallel, and Loop workflow agents.

**Dependencies**: Phase 2

### Tasks

- [ ] **3.1** Implement SequentialAgent (`lib/adk/agent/sequential_agent.ex`)
- [ ] **3.2** Implement ParallelAgent (`lib/adk/agent/parallel_agent.ex`)
  - Task.async_stream with branch isolation
- [ ] **3.3** Implement LoopAgent (`lib/adk/agent/loop_agent.ex`)
  - max_iterations, escalation-based termination
- [ ] **3.4** Implement agent transfer mechanism in AutoFlow
- [ ] **3.5** Integration tests for multi-agent workflows

---

## Phase 4: A2A Protocol

**Goal**: Implement the Agent-to-Agent protocol for inter-agent HTTP communication.

**Dependencies**: Phase 3

### Tasks

- [ ] **4.1** Implement AgentCard builder (`lib/adk/a2a/agent_card.ex`)
- [ ] **4.2** Implement ADK <-> A2A converters (`lib/adk/a2a/converter.ex`)
- [ ] **4.3** Implement A2A Server (`lib/adk/a2a/server.ex`) - Plug endpoint
- [ ] **4.4** Implement A2A Client (`lib/adk/a2a/client.ex`)
- [ ] **4.5** Implement RemoteA2aAgent (`lib/adk/agent/remote_agent.ex`)

---

## Phase 5: Supporting Services

**Goal**: Memory, artifacts, plugins, MCP, and remaining features.

**Dependencies**: Phase 3

### Tasks

- [ ] **5.1** Implement Memory service behaviour + InMemoryMemoryService
- [ ] **5.2** Implement Artifact service behaviour + InMemoryArtifactService
- [ ] **5.3** Implement Plugin system (behaviour + chain execution)
- [ ] **5.4** Implement MCP toolset integration
- [ ] **5.5** Implement DatabaseSessionService (Ecto)
- [ ] **5.6** Telemetry integration

---

## Dependency Graph

```
Phase 1: Foundation          <-- COMPLETE
    |
    v
Phase 2: Runner + Tools + LLM Agent
    |
    v
Phase 3: Orchestration Agents
    |
    +--------+---------+
    |                  |
    v                  v
Phase 4: A2A     Phase 5: Supporting Services
```

Phases 4 and 5 can be developed in parallel after Phase 3.

---

## Key Reference Files (Go ADK)

| ADK Component | Go Source File |
|---------------|----------------|
| Agent interface | `/workspace/adk-go/agent/agent.go` |
| Agent contexts | `/workspace/adk-go/agent/context.go` |
| RunConfig | `/workspace/adk-go/agent/run_config.go` |
| Session/Event structs | `/workspace/adk-go/session/session.go` |
| Session service | `/workspace/adk-go/session/service.go` |
| InMemory sessions | `/workspace/adk-go/session/inmemory.go` |
| State utilities | `/workspace/adk-go/internal/sessionutils/utils.go` |
| Runner | `/workspace/adk-go/runner/runner.go` |
| LLM Agent | `/workspace/adk-go/agent/llm_agent.go` |
| Flow | `/workspace/adk-go/agent/flow.go` |
| Tool interface | `/workspace/adk-go/tool/tool.go` |
| A2A server | `/workspace/adk-go/server/adka2a/` |

---

## Key Risks per Phase

| Phase | Risk | Mitigation |
|-------|------|------------|
| 2 | No Elixir GenAI SDK | Use Req + REST API directly; study Go SDK for patterns |
| 2 | SSE parsing complexity | Study Go/Python implementations for chunked response handling |
| 3 | Parallel agent state races | Use ETS with atomic operations; branch isolation |
| 4 | A2A spec ambiguity | Reference Go A2A SDK at `/workspace/a2a-go/` |
