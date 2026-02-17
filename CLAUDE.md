# Elixir ADK - Claude CLI Instructions

## Project Overview

Elixir/OTP port of Google's Agent Development Kit (ADK). Standalone `adk_ex` hex package providing agent orchestration, session management, tool use, and LLM abstraction. Transport-agnostic — no HTTP/Plug dependencies.

**Note**: The A2A (Agent-to-Agent) protocol is a separate package at `/workspace/elixir_code/a2a_ex/` (github.com/JohnSmall/a2a_ex). It depends on this ADK package via `{:adk_ex, path: "../adk_ex"}` and adds HTTP server/client layers.

**Note**: Example A2A applications are at `/workspace/elixir_code/a2a_ex_examples/` (research+report, code+review, data+viz).

## Quick Start

```bash
cd /workspace/elixir_code/adk_ex
mix deps.get
mix test          # 240 tests
mix credo         # Static analysis
mix dialyzer      # Type checking
```

## Key Documentation

- **PRD**: `docs/prd.md` — Requirements, design decisions, component status
- **Implementation Plan**: `docs/implementation-plan.md` — Phase checklist with detailed tasks
- **Onboarding**: `docs/onboarding.md` — Full context for new agents (architecture, patterns, gotchas)

## Reference Codebases

- **Go ADK (PRIMARY)**: `/workspace/samples/adk-go/` — Read corresponding Go file before implementing any module
- **Python ADK**: `/workspace/google-adk-venv/lib/python3.13/site-packages/google/adk/`
- **A2A Go SDK**: `/workspace/samples/a2a-go/`
- **A2A Samples**: `/workspace/samples/a2a-samples/`

## Current Status

**Phases 1-5 COMPLETE (240 tests adk_ex + 21 tests adk_ex_ecto, credo clean, dialyzer clean).**

| Phase | Status | Tests |
|-------|--------|-------|
| Phase 1: Foundation (Types, Event, Session, Agent) | Done | 75 |
| Phase 2: Runner + Tools + LLM Agent (Model, Flow) | Done | +63 = 138 |
| Phase 3: Orchestration (Loop/Sequential/Parallel, Transfer) | Done | +30 = 168 |
| Phase 4: Memory, Artifacts, Telemetry | Done | +49 = 217 |
| Phase 5: Plugins, Toolsets, Database Sessions | Done | +23 = 240 (+21 adk_ex_ecto) |

## Module Map

### Core (Phase 1)
- `ADK.Types` — Content, Part, FunctionCall, FunctionResponse, Blob
- `ADK.Event` + `ADK.Event.Actions` — Event struct with side-effects
- `ADK.Session` + `ADK.Session.State` — Session struct + prefix-based state scoping
- `ADK.Session.Service` + `ADK.Session.InMemory` — Session storage behaviour + ETS impl
- `ADK.RunConfig` — Runtime configuration
- `ADK.Agent` — Agent behaviour (name, description, run, sub_agents)
- `ADK.Agent.InvocationContext` + `ADK.Agent.CallbackContext` — Execution contexts
- `ADK.Agent.Config` + `ADK.Agent.CustomAgent` — Custom agents
- `ADK.Agent.Tree` — Agent tree utilities (find, parent_map, validate)

### Runner + Tools + LLM (Phase 2)
- `ADK.Model` + `ADK.Model.LlmRequest` + `ADK.Model.LlmResponse` — LLM abstraction
- `ADK.Model.Mock` / `ADK.Model.Gemini` / `ADK.Model.Claude` — Providers
- `ADK.Model.Registry` — Model name → provider resolution
- `ADK.Tool` + `ADK.Tool.Context` + `ADK.Tool.FunctionTool` — Tool system
- `ADK.Flow` — Stream.resource/3 state machine (max 25 iterations)
- `ADK.Flow.Processors.*` — Basic, ToolProcessor, Instructions, AgentTransfer, Contents
- `ADK.Agent.LlmAgent` — LLM-powered agent with model + tools + callbacks
- `ADK.Runner` — Session lifecycle, event persistence, agent resolution

### Orchestration (Phase 3)
- `ADK.Agent.LoopAgent` — Iterate sub-agents with max_iterations, escalation exit
- `ADK.Agent.SequentialAgent` — LoopAgent wrapper (max_iterations=1)
- `ADK.Agent.ParallelAgent` — Task.async + Task.await_many, branch isolation
- `ADK.Tool.TransferToAgent` — Tool signaling agent transfer
- `ADK.Flow.Processors.AgentTransfer` — Injects transfer tool + target instructions

### Services (Phase 4)
- `ADK.Memory.Entry` — Memory entry struct (content, author, timestamp)
- `ADK.Memory.Service` + `ADK.Memory.InMemory` — Memory behaviour + GenServer/ETS impl
- `ADK.Artifact.Service` + `ADK.Artifact.InMemory` — Artifact behaviour + versioned GenServer/ETS impl
- `ADK.Tool.LoadMemory` — Tool: searches memory via context
- `ADK.Tool.LoadArtifacts` — Tool: loads artifacts by name
- `ADK.Telemetry` — Dual telemetry: OpenTelemetry spans + Elixir :telemetry events

### Plugins, Toolsets, Database Sessions (Phase 5)
- `ADK.Plugin` — Plugin struct with 12 callback fields (Runner/Agent/Model/Tool level hooks)
- `ADK.Plugin.Manager` — Chains plugins in order, first non-nil wins. All `run_*` accept nil (no-op).
- `ADK.Tool.Toolset` — Behaviour for dynamic tool providers (`name/1`, `tools/2`)
- `ADK.Runner` — Now has `plugins` field and `session_module` field (default `ADK.Session.InMemory`) for pluggable session backends
- `ADK.Agent.InvocationContext` — Now has `plugin_manager` field

### Database Sessions (separate package)
- **Package**: `adk_ex_ecto` at `/workspace/elixir_code/adk_ex_ecto/` (github.com/JohnSmall/adk_ex_ecto)
- `ADKExEcto.SessionService` — Implements `ADK.Session.Service` via Ecto
- `ADKExEcto.Migration` — Creates 4 tables (adk_sessions, adk_events, adk_app_states, adk_user_states)
- `ADKExEcto.Schemas.*` — Ecto schemas for Session, Event, AppState, UserState
- Supports SQLite3 (dev/test) and PostgreSQL (prod)

## Critical Rules

1. **Compile order**: Define nested/referenced modules BEFORE parent modules in the same file (e.g., `Event.Actions` before `Event`)
2. **Avoid MapSet with dialyzer**: Use `%{key => true}` maps + `Map.has_key?/2` instead
3. **Credo nesting**: Max depth 2 — extract inner logic into helper functions
4. **Mock model**: Use `Mock.new(responses: [...])` NOT bare `%Mock{}` — needs Agent process for state
5. **Behaviour dispatch**: `ADK.Agent` has NO module functions — call `agent.__struct__.run(agent, ctx)` or the implementing module directly
6. **Test module names**: Use unique names to avoid cross-file collisions (e.g., `LoopAgentTest.Helper` not `FakeAgent`)
7. **All tests async**: Use `async: true` unless shared state requires otherwise
8. **Verify all changes**: Always run `mix test && mix credo && mix dialyzer`
9. **Telemetry events**: Use `[:adk_ex, ...]` prefix (not `[:adk, ...]`) — renamed with hex package
10. **OTel span testing**: `config/test.exs` configures `otel_simple_processor`. Call `:otel_simple_processor.set_exporter(:otel_exporter_pid, self())` in test setup. Span name is `elem(span, 6)` (not 2). No app restart needed.
11. **Dialyzer unreachable branches**: If return type is always `{:ok, _}`, don't match `{:error, _}`
12. **FunctionTool field**: Use `handler:` not `function:` in `FunctionTool.new/1`
13. **Plugin nil safety**: All `Plugin.Manager.run_*` functions accept `nil` as first arg — no nil checks needed at call sites
14. **SQLite in-memory testing**: Don't use Ecto sandbox with pool_size 1. Clean tables in setup instead.
15. **OpenTelemetry dep**: `{:opentelemetry, "~> 1.5"}` must NOT have `only: [:dev, :test]` — needed at compile time in all environments.
16. **Dep name must match app name**: Downstream projects must use `{:adk_ex, path: "..."}` (not `{:adk, ...}`). Mix fails when dep name != app name.

## Architecture Quick Reference

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

### Plugin Execution Order
Plugins run **before** agent callbacks at every hook point. If a plugin returns non-nil, agent callbacks are skipped entirely (short-circuit).

### Callback Pattern
All callbacks return `{value | nil, updated_context}`. Nil = continue, non-nil = short-circuit.

### State Prefixes
- `(none)` = session-local, `app:` = cross-session, `user:` = cross-user-session, `temp:` = invocation-only
