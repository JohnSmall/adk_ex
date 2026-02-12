# Product Requirements Document: Elixir ADK (Agent Development Kit)

## Document Info
- **Project**: Elixir ADK - An Elixir/OTP port of Google's Agent Development Kit
- **Version**: 0.5.0
- **Date**: 2026-02-08
- **Status**: Phases 1-5 Complete (240 tests adk_ex + 21 tests adk_ex_ecto)
- **GitHub**: github.com/JohnSmall/adk_ex

---

## 1. Executive Summary

This project ports Google's Agent Development Kit (ADK) to Elixir/OTP. The Google ADK provides a framework for building AI agents with tools, multi-agent orchestration, session management, and callback hooks. Elixir's BEAM VM, with its native concurrency, fault tolerance, and message-passing primitives, is an ideal platform for agent systems.

The Elixir ADK is a standalone Mix project (hex package: `adk_ex`) that provides idiomatic Elixir equivalents of all core ADK components while leveraging OTP patterns where they naturally fit.

**Note**: The A2A (Agent-to-Agent) protocol is implemented as a separate package, `a2a_ex`, at `/workspace/a2a_ex/`. It depends on this ADK package and adds HTTP server/client layers for agent interoperability.

---

## 2. Background and Motivation

### 2.1 Current State
- Google ADK exists in Python (reference), TypeScript, Go, and Java
- No Elixir implementation exists
- The A2A protocol is an open standard (https://github.com/a2aproject/A2A) for agent interoperability

### 2.2 Why Elixir?
- **BEAM processes** map naturally to agents (lightweight, isolated, concurrent)
- **OTP supervision trees** provide built-in fault tolerance for agent systems
- **Stream.resource/3** provides lazy enumerables matching the ADK's async generator pattern
- **Task.async/await_many** handles parallel agent execution natively
- **ETS** provides fast in-memory state storage with concurrent reads
- **Behaviours** replace class inheritance with explicit contracts

### 2.3 Reference Materials
- **Google ADK Go source** (PRIMARY): `/workspace/adk-go/`
- **Google ADK Python source**: `/workspace/google-adk-venv/lib/python3.13/site-packages/google/adk/`
- **Google ADK docs**: https://google.github.io/adk-docs/

---

## 3. Goals and Non-Goals

### 3.1 Goals
1. **Feature parity with Google ADK core** - All agent types, runner, session, event, tool, and callback systems
2. **Idiomatic Elixir** - Use OTP patterns, behaviours, and conventions
3. **Multi-LLM support** - Gemini (primary), Claude (Anthropic), and extensible via behaviour
4. **Production-ready services** - In-memory + persistent implementations for sessions, artifacts, memory
5. **Comprehensive testing** - Unit tests, integration tests, dialyzer, credo
6. **Hex-publishable** - Standalone package with no A2A or HTTP dependencies

### 3.2 Non-Goals (for this package)
- A2A protocol (separate `a2a_ex` package)
- Google Cloud-specific integrations (Vertex AI, GCS, Agent Engine)
- Web UI / CLI tool
- Streaming/BIDI audio/video support
- Evaluation framework

---

## 4. Core Architecture

```
User Message -> Runner -> Agent -> Flow -> LLM
                  |          |        |       |
              [plugins]  [plugins] [plugins]  |
                  |          |     [tool calls loop]
                  |          |     [agent transfer]
                  |          |     [toolset resolution]
                  |          |        |
               [commits events + state to Session]
                  |
               [yields Events to application]
```

### Component Status

| Component | Module | Status |
|-----------|--------|--------|
| Core types (Content, Part, etc.) | `ADK.Types.*` | Done (Phase 1) |
| Event + Actions | `ADK.Event`, `ADK.Event.Actions` | Done (Phase 1) |
| Session | `ADK.Session` | Done (Phase 1) |
| Session State utilities | `ADK.Session.State` | Done (Phase 1) |
| Session Service behaviour | `ADK.Session.Service` | Done (Phase 1) |
| InMemory Session Service | `ADK.Session.InMemory` | Done (Phase 1) |
| Run Config | `ADK.RunConfig` | Done (Phase 1) |
| Agent behaviour | `ADK.Agent` | Done (Phase 1) |
| Invocation Context | `ADK.Agent.InvocationContext` | Done (Phase 1) |
| Callback Context | `ADK.Agent.CallbackContext` | Done (Phase 1) |
| Custom Agent | `ADK.Agent.CustomAgent` | Done (Phase 1) |
| Agent Config | `ADK.Agent.Config` | Done (Phase 1) |
| Agent Tree utilities | `ADK.Agent.Tree` | Done (Phase 1) |
| Model behaviour | `ADK.Model` | Done (Phase 2) |
| LlmRequest / LlmResponse | `ADK.Model.LlmRequest`, `ADK.Model.LlmResponse` | Done (Phase 2) |
| Mock model | `ADK.Model.Mock` | Done (Phase 2) |
| Gemini provider | `ADK.Model.Gemini` | Done (Phase 2) |
| Claude provider | `ADK.Model.Claude` | Done (Phase 2) |
| Model Registry | `ADK.Model.Registry` | Done (Phase 2) |
| Tool behaviour | `ADK.Tool` | Done (Phase 2) |
| Tool Context | `ADK.Tool.Context` | Done (Phase 2) |
| Function Tool | `ADK.Tool.FunctionTool` | Done (Phase 2) |
| Flow engine | `ADK.Flow` | Done (Phase 2) |
| Request processors (5) | `ADK.Flow.Processors.*` | Done (Phase 2-3) |
| LLM Agent | `ADK.Agent.LlmAgent` | Done (Phase 2) |
| Runner | `ADK.Runner` | Done (Phase 2) |
| Loop Agent | `ADK.Agent.LoopAgent` | Done (Phase 3) |
| Sequential Agent | `ADK.Agent.SequentialAgent` | Done (Phase 3) |
| Parallel Agent | `ADK.Agent.ParallelAgent` | Done (Phase 3) |
| Transfer-to-Agent tool | `ADK.Tool.TransferToAgent` | Done (Phase 3) |
| Agent Transfer processor | `ADK.Flow.Processors.AgentTransfer` | Done (Phase 3) |
| Memory service | `ADK.Memory.*` | Done (Phase 4) |
| Artifact service | `ADK.Artifact.*` | Done (Phase 4) |
| LoadMemory tool | `ADK.Tool.LoadMemory` | Done (Phase 4) |
| LoadArtifacts tool | `ADK.Tool.LoadArtifacts` | Done (Phase 4) |
| Telemetry (OTel + :telemetry) | `ADK.Telemetry` | Done (Phase 4) |
| Plugin struct | `ADK.Plugin` | Done (Phase 5) |
| Plugin manager | `ADK.Plugin.Manager` | Done (Phase 5) |
| Toolset behaviour | `ADK.Tool.Toolset` | Done (Phase 5) |
| Database session service | `ADKExEcto.SessionService` | Done (Phase 5, separate package) |

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Behaviours over inheritance | Elixir has no class inheritance; behaviours + structs provide contracts |
| GenServer + ETS for InMemorySession | Serialized writes via GenServer, concurrent reads via ETS |
| Stream.resource/3 for event iteration | Lazy enumerables match async generators; state machine pattern |
| Structs for data models | Replaces Pydantic models; use typed structs |
| Modules defined before dependents | Nested structs must be compiled first (e.g., Event.Actions before Event) |
| Plain maps over MapSet for tracking | Avoids dialyzer opaque type issues with MapSet |
| Agent process for Mock model state | Mock.new/1 starts an Agent process so sequential responses advance across flow iterations |
| Req for HTTP | Modern Elixir HTTP client for LLM provider API calls |
| Callbacks return `{value \| nil, context}` | nil = continue, non-nil = short-circuit; consistent across all hook points |
| Flow as single module (not Single/Auto) | Simpler; one flow handles both text-only and tool-loop cases |
| SequentialAgent wraps LoopAgent | `max_iterations: 1` — matches Go ADK pattern, avoids code duplication |
| ParallelAgent uses Task.async | No TaskSupervisor needed — parent process supervises |
| A2A as separate package | ADK is transport-agnostic; A2A adds HTTP/Plug deps |
| Transfer in Flow, not Runner | Transfer executes immediately after tool call, same turn |
| Plugins run before agent callbacks | First non-nil return short-circuits; consistent priority order |
| Toolset behaviour for dynamic tools | Runtime tool resolution; foundation for future MCP integration |
| Database sessions as separate package | `adk_ex_ecto` keeps Ecto/DB deps out of core `adk_ex` |
| Session dispatch via module field | `Runner.session_module` enables pluggable session backends |

---

## 5. Detailed Requirements

### 5.1 Agent System
- Base agent behaviour defining `run/2` returning Enumerable of Events
- LLM agent with model, instruction, tools, sub_agents, callbacks
- LoopAgent: iterate sub-agents with max_iterations, escalation exit, state propagation
- SequentialAgent: thin LoopAgent wrapper (max_iterations=1)
- ParallelAgent: concurrent Task.async with branch isolation
- Custom agent via Config struct with before/after callbacks
- Agent tree: find_agent/2, build_parent_map/1, validate_unique_names/1
- Agent transfer via `transfer_to_agent` tool detected in Flow

### 5.2 Runner and Event Loop
- Runner managing user invocations with session auto-creation
- Event processing: append to session, commit state_delta and artifact_delta
- Partial event forwarding without action processing
- RunConfig: streaming_mode, save_input_blobs_as_artifacts
- find_agent_to_run: function response matching, transfer_to_agent check, history scan, root fallback

### 5.3 Session Management
- Session struct: id, app_name, user_id, events, state, last_update_time
- SessionService behaviour: create, get, list, delete, append_event
- InMemorySessionService backed by 3 ETS tables (sessions, app_state, user_state)
- State prefix scoping: `app:`, `user:`, `temp:`, (none)=session
- State delta extraction and merge utilities

### 5.4 Event System
- Event struct with UUID auto-generation and timestamp
- EventActions: state_delta, artifact_delta, transfer_to_agent, escalate, skip_summarization
- final_response?/1 detection logic matching Go ADK

### 5.5 Tool System
- Tool behaviour: name, description, declaration, run, long_running?
- FunctionTool wrapping anonymous functions with try/rescue error handling
- TransferToAgent tool returning `%{"transfer_to_agent" => name}` in result
- ToolContext with state access (3-level delegation: tool -> callback -> session)
- Tool declaration as JSON Schema map

### 5.6 LLM Abstraction
- Model behaviour: name/1, generate_content/3 returning Enumerable of LlmResponse
- Gemini provider via REST API (Req)
- Claude provider via REST API (Req)
- Model Registry for name-based resolution
- Mock model with stateful sequential responses (Agent process)

### 5.7 Flow Engine
- Stream.resource/3 state machine with max 25 iterations
- 5 request processors: Basic, ToolProcessor, Instructions, AgentTransfer, Contents
- 6 callback hooks: before/after model, before/after tool, on_model_error, on_tool_error
- Tool execution with error recovery and action merging across parallel calls
- Agent transfer: maybe_set_transfer detects transfer result, maybe_run_transfer executes target agent

---

## 6. Technical Constraints

- **Elixir version**: >= 1.17
- **OTP version**: >= 26
- **Runtime dependencies**: jason, elixir_uuid, req, opentelemetry_api, opentelemetry, telemetry
- **Dev/test dependencies**: ex_doc, dialyxir, credo
- **No GenAI SDK**: Direct REST API calls for LLM providers
- **No HTTP server deps**: No plug, phoenix, bandit (those belong in a2a_ex)
- **No Ecto in core**: Database persistence via separate `adk_ex_ecto` package (github.com/JohnSmall/adk_ex_ecto)
- **Testing**: ExUnit, dialyzer, credo

---

## 7. Success Criteria

1. All agent types work with real LLM providers (Gemini, Claude)
2. Sessions persist and restore across runner invocations
3. Agent transfer chains correctly between parent and child agents
4. Orchestration agents (Sequential, Parallel, Loop) work with escalation and state propagation
5. All core behaviours have at least one in-memory implementation
6. Test suite passes (240 adk_ex + 21 adk_ex_ecto), dialyzer clean, credo clean
7. Package publishable to hex.pm with no A2A/HTTP dependencies
