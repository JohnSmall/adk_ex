# Onboarding Guide: Elixir ADK Project

## For New AI Agents / Developers

This document provides everything needed to pick up the Elixir ADK project.

---

## 1. What Is This Project?

We are building an **Elixir/OTP port of Google's Agent Development Kit (ADK)**. The Google ADK is a framework for building AI agents that can use tools, orchestrate sub-agents, manage sessions, and communicate with other agents.

Google provides the ADK in Python (reference), TypeScript, Go, and Java. We are creating the Elixir implementation.

**Note**: The A2A (Agent-to-Agent) protocol is a separate package at `/workspace/a2a_ex/` (github.com/JohnSmall/a2a_ex). It depends on this ADK package.

---

## 2. Current Status

**All 5 phases are COMPLETE.** The project lives at `/workspace/adk_ex/` (github.com/JohnSmall/adk_ex). Database persistence is in a separate package at `/workspace/adk_ex_ecto/` (github.com/JohnSmall/adk_ex_ecto).

### What's Built

#### Phase 1: Foundation (75 tests)

| Module | Purpose | File |
|--------|---------|------|
| `ADK.Types.Blob` | Binary data with MIME type | `lib/adk/types.ex` |
| `ADK.Types.FunctionCall` | LLM function call request | `lib/adk/types.ex` |
| `ADK.Types.FunctionResponse` | Function call response | `lib/adk/types.ex` |
| `ADK.Types.Part` | Tagged union: text/fc/fr/blob | `lib/adk/types.ex` |
| `ADK.Types.Content` | Message with role + parts | `lib/adk/types.ex` |
| `ADK.Types` | Helper functions for Content | `lib/adk/types.ex` |
| `ADK.Event.Actions` | Side-effects: state_delta, transfer, escalate | `lib/adk/event.ex` |
| `ADK.Event` | Core event struct with new/1, final_response?/1 | `lib/adk/event.ex` |
| `ADK.Session` | Session struct (id, app_name, user_id, state, events) | `lib/adk/session.ex` |
| `ADK.Session.State` | Prefix-based state scoping utilities | `lib/adk/session/state.ex` |
| `ADK.Session.Service` | Behaviour for session storage backends | `lib/adk/session/service.ex` |
| `ADK.Session.InMemory` | GenServer + 3 ETS tables session implementation | `lib/adk/session/in_memory.ex` |
| `ADK.RunConfig` | Runtime config (streaming_mode, save_blobs) | `lib/adk/run_config.ex` |
| `ADK.Agent` | Agent behaviour (name, description, run, sub_agents) | `lib/adk/agent.ex` |
| `ADK.Agent.InvocationContext` | Immutable execution context | `lib/adk/agent/invocation_context.ex` |
| `ADK.Agent.CallbackContext` | Callback context with state access | `lib/adk/agent/callback_context.ex` |
| `ADK.Agent.Config` | Configuration struct for custom agents | `lib/adk/agent/config.ex` |
| `ADK.Agent.CustomAgent` | Custom agent with before/after callbacks | `lib/adk/agent/custom_agent.ex` |
| `ADK.Agent.Tree` | Agent tree: find, parent_map, validate | `lib/adk/agent/tree.ex` |

#### Phase 2: Runner + Tool System + LLM Agent (+63 tests = 138 total)

| Module | Purpose | File |
|--------|---------|------|
| `ADK.Model` | Model behaviour (name/1, generate_content/3) | `lib/adk/model.ex` |
| `ADK.Model.LlmRequest` | LLM request struct | `lib/adk/model/llm_request.ex` |
| `ADK.Model.LlmResponse` | LLM response struct | `lib/adk/model/llm_response.ex` |
| `ADK.Model.Mock` | Stateful mock model via Agent process | `lib/adk/model/mock.ex` |
| `ADK.Model.Gemini` | Gemini REST API provider (Req) | `lib/adk/model/gemini.ex` |
| `ADK.Model.Claude` | Claude/Anthropic REST API provider (Req) | `lib/adk/model/claude.ex` |
| `ADK.Model.Registry` | Model name -> provider resolution | `lib/adk/model/registry.ex` |
| `ADK.Tool` | Tool behaviour + module-level dispatch | `lib/adk/tool.ex` |
| `ADK.Tool.Context` | Tool context with 3-level state delegation | `lib/adk/tool/context.ex` |
| `ADK.Tool.FunctionTool` | Anonymous function wrapper with try/rescue | `lib/adk/tool/function_tool.ex` |
| `ADK.Flow` | Flow engine (Stream.resource/3, max 25 iter) | `lib/adk/flow.ex` |
| `ADK.Flow.Processors.Basic` | Copies generate_content_config into request | `lib/adk/flow/processors/basic.ex` |
| `ADK.Flow.Processors.ToolProcessor` | Populates tools map + function declarations | `lib/adk/flow/processors/tool_processor.ex` |
| `ADK.Flow.Processors.Instructions` | System instruction + {variable} interpolation | `lib/adk/flow/processors/instructions.ex` |
| `ADK.Flow.Processors.Contents` | Conversation history from session events | `lib/adk/flow/processors/contents.ex` |
| `ADK.Agent.LlmAgent` | LLM-powered agent (model, tools, callbacks) | `lib/adk/agent/llm_agent.ex` |
| `ADK.Runner` | Runner (session lifecycle, event persistence) | `lib/adk/runner.ex` |

#### Phase 3: Orchestration Agents + Agent Transfer (+30 tests = 168 total)

| Module | Purpose | File |
|--------|---------|------|
| `ADK.Agent.LoopAgent` | Iterates sub-agents (max_iterations, escalation) | `lib/adk/agent/loop_agent.ex` |
| `ADK.Agent.SequentialAgent` | Runs sub-agents once in order (wraps LoopAgent) | `lib/adk/agent/sequential_agent.ex` |
| `ADK.Agent.ParallelAgent` | Runs sub-agents concurrently (Task.async) | `lib/adk/agent/parallel_agent.ex` |
| `ADK.Tool.TransferToAgent` | Tool signaling agent transfer | `lib/adk/tool/transfer_to_agent.ex` |
| `ADK.Flow.Processors.AgentTransfer` | Injects transfer tool + target instructions | `lib/adk/flow/processors/agent_transfer.ex` |

#### Phase 4: Memory, Artifacts, and Telemetry (+49 tests = 217 total)

| Module | Purpose | File |
|--------|---------|------|
| `ADK.Memory.Entry` | Memory entry struct (content, author, timestamp) | `lib/adk/memory/entry.ex` |
| `ADK.Memory.Service` | Behaviour: add_session/2, search/2 | `lib/adk/memory/service.ex` |
| `ADK.Memory.InMemory` | GenServer + ETS, word-based search | `lib/adk/memory/in_memory.ex` |
| `ADK.Artifact.Service` | Behaviour: save, load, delete, list, versions | `lib/adk/artifact/service.ex` |
| `ADK.Artifact.InMemory` | GenServer + ETS, versioned storage, user-scoped | `lib/adk/artifact/in_memory.ex` |
| `ADK.Tool.LoadMemory` | Tool: searches memory via context | `lib/adk/tool/load_memory.ex` |
| `ADK.Tool.LoadArtifacts` | Tool: loads artifacts by name | `lib/adk/tool/load_artifacts.ex` |
| `ADK.Telemetry` | Dual: OpenTelemetry spans + :telemetry events | `lib/adk/telemetry.ex` |

#### Phase 5: Plugins, Toolsets, and Database Sessions (+23 tests = 240 total, +21 in adk_ex_ecto)

| Module | Purpose | File |
|--------|---------|------|
| `ADK.Plugin` | Plugin struct with 12 callback fields + new/1 | `lib/adk/plugin.ex` |
| `ADK.Plugin.Manager` | Chains plugins, first non-nil wins, nil-safe | `lib/adk/plugin/manager.ex` |
| `ADK.Tool.Toolset` | Behaviour for dynamic tool providers | `lib/adk/tool/toolset.ex` |
| `ADK.Runner` (updated) | Added `plugins`, `session_module` fields | `lib/adk/runner.ex` |
| `ADK.Flow` (updated) | Plugin hooks at model/tool level, toolset resolution | `lib/adk/flow.ex` |
| `ADK.Agent.LlmAgent` (updated) | Plugin before/after agent, `toolsets` field | `lib/adk/agent/llm_agent.ex` |
| `ADK.Agent.InvocationContext` (updated) | Added `plugin_manager` field | `lib/adk/agent/invocation_context.ex` |

#### Database Sessions (separate package: `adk_ex_ecto`, 21 tests)

| Module | Purpose | File |
|--------|---------|------|
| `ADKExEcto.SessionService` | Ecto-backed session service | `lib/adk_ex_ecto/session_service.ex` |
| `ADKExEcto.Migration` | Creates 4 tables with composite PKs | `lib/adk_ex_ecto/migration.ex` |
| `ADKExEcto.Schemas.Session` | Sessions table schema | `lib/adk_ex_ecto/schemas/session.ex` |
| `ADKExEcto.Schemas.Event` | Events table schema | `lib/adk_ex_ecto/schemas/event.ex` |
| `ADKExEcto.Schemas.AppState` | App state table schema | `lib/adk_ex_ecto/schemas/app_state.ex` |
| `ADKExEcto.Schemas.UserState` | User state table schema | `lib/adk_ex_ecto/schemas/user_state.ex` |

### Test Coverage
- **adk_ex**: 240 tests passing (75 + 63 + 30 + 49 + 23)
- **adk_ex_ecto**: 21 tests passing
- 4 integration tests (Gemini + Claude, excluded by default)
- Credo: clean (both packages)
- Dialyzer: clean (both packages)

### Project Status
All 5 phases are complete. See `docs/implementation-plan.md` for full details.

---

## 3. Key Resources

### Local Files

| Resource | Location |
|----------|----------|
| **This project (Elixir ADK)** | `/workspace/adk_ex/` |
| **Database sessions (separate package)** | `/workspace/adk_ex_ecto/` |
| **A2A protocol (separate package)** | `/workspace/a2a_ex/` |
| **Google ADK Go source (PRIMARY ref)** | `/workspace/adk-go/` |
| **Google ADK Python source** | `/workspace/google-adk-venv/lib/python3.13/site-packages/google/adk/` |
| **A2A Go SDK** | `/workspace/a2a-go/` |
| **A2A samples** | `/workspace/a2a-samples/` |
| **PRD** | `/workspace/adk_ex/docs/prd.md` |
| **Architecture** | `/workspace/adk_ex/docs/architecture.md` |
| **Implementation plan** | `/workspace/adk_ex/docs/implementation-plan.md` |
| **This guide** | `/workspace/adk_ex/docs/onboarding.md` |

### External Documentation

| Resource | URL |
|----------|-----|
| Google ADK docs | https://google.github.io/adk-docs/ |
| A2A protocol spec | https://github.com/a2aproject/A2A |

---

## 4. Architecture Quick Reference

### Core Execution Model

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

### Execution Flow Detail

```
Runner.run/5
  |-- Get/create session from SessionService (via runner.session_module)
  |-- [plugin: on_user_message] (may modify user content)
  |-- Append user message event
  |-- [plugin: before_run] (may short-circuit entire run)
  |-- Find agent to run (transfer check -> history scan -> root)
  +-- LlmAgent.run/2
        |-- [plugin: before_agent] -> [before_agent_callbacks] (may short-circuit)
        |-- Flow.run/2 (Stream.resource/3 loop)
        |     |-- Resolve toolsets (dynamic tool providers)
        |     |-- Build LlmRequest via 5 processors:
        |     |     Basic -> ToolProcessor -> Instructions -> AgentTransfer -> Contents
        |     |-- [plugin: before_model] -> [before_model_callbacks] (may short-circuit)
        |     |-- Model.generate_content/3 (Gemini/Claude/Mock)
        |     |-- [plugin: after_model] -> [after_model_callbacks] (may replace)
        |     |-- If function_calls in response:
        |     |     [plugin: before_tool] -> [before_tool] -> Tool.run/3
        |     |     -> maybe_set_transfer -> [plugin: after_tool] -> [after_tool]
        |     |     If transfer_to_agent set: run target agent (maybe_run_transfer)
        |     |     Build tool response event -> loop back to LLM
        |     +-- If text response (final): emit event, halt
        |-- [plugin: after_agent] -> [after_agent_callbacks] (may short-circuit)
        +-- If output_key: save text to state_delta
  |-- For each event: [plugin: on_event] (may modify)
  +-- [plugin: after_run] (notification)
```

### Agent Types

| Type | Purpose | Implementation |
|------|---------|----------------|
| CustomAgent | User-defined run function | Config struct with run fn |
| LlmAgent | LLM-powered with tools | Flow engine + request processors |
| LoopAgent | Repeat sub-agents until termination | Stream.resource + reduce_while |
| SequentialAgent | Run sub-agents in order once | LoopAgent with max_iterations=1 |
| ParallelAgent | Run sub-agents concurrently | Task.async + Task.await_many |

### Callback Points

All callbacks return `{value | nil, updated_context}`. Nil = continue, non-nil = short-circuit.

| Hook | Signature | Short-circuit |
|------|-----------|---------------|
| before_agent | `(CallbackContext -> {Content \| nil, CallbackContext})` | Non-nil Content skips agent |
| after_agent | `(CallbackContext -> {Content \| nil, CallbackContext})` | Non-nil Content replaces output |
| before_model | `(CallbackContext, LlmRequest -> {LlmResponse \| nil, CallbackContext})` | Non-nil LlmResponse skips LLM |
| after_model | `(CallbackContext, LlmResponse -> {LlmResponse \| nil, CallbackContext})` | Non-nil LlmResponse replaces |
| before_tool | `(ToolContext, tool, args -> {map \| nil, ToolContext})` | Non-nil map skips tool |
| after_tool | `(ToolContext, tool, args, result -> {map \| nil, ToolContext})` | Non-nil map replaces result |

**Plugin hooks** (Phase 5): Plugins use the same callback signatures but run **before** agent callbacks. If a plugin returns non-nil, agent callbacks are skipped entirely. Additional plugin-only hooks: `on_user_message`, `before_run`, `after_run` (notification only), `on_event`.

### State Prefixes

| Prefix | Scope | Persisted? |
|--------|-------|------------|
| (none) | Session-local | Yes |
| `app:` | Shared across all users/sessions | Yes |
| `user:` | Shared across user's sessions | Yes |
| `temp:` | Current invocation only | No (discarded) |

---

## 5. Elixir/OTP Design Patterns Used

| ADK Concept | Elixir Equivalent | Why |
|-------------|-------------------|-----|
| BaseAgent (class) | `@behaviour` + struct | No inheritance in Elixir |
| Agent.Run() stream | `Stream.resource/3` | Lazy evaluation, yield/resume |
| Session storage | GenServer + 3 ETS tables | Serialized writes, concurrent reads |
| Async generators | `Enumerable.t()` (Stream) | Flow.run returns Stream of Events |
| Pydantic models | `defstruct` + `@type` | Typed structs with `@enforce_keys` |
| Dynamic dispatch | `agent.__struct__.run(agent, ctx)` | Polymorphism via struct module |
| ParallelAgent concurrency | `Task.async` + `Task.await_many` | BEAM lightweight processes |
| SequentialAgent | LoopAgent(max_iterations=1) | Code reuse, matches Go pattern |

### Package Naming

- **Hex package name**: `adk_ex` (OTP app: `:adk_ex`)
- **Module names**: `ADK.*` (module prefix is independent of hex name, like `phoenix` uses `Phoenix.*`)
- **Source paths**: `lib/adk/`, `test/adk/` (unchanged)
- **Telemetry events**: `[:adk_ex, :llm | :tool, :start | :stop | :exception]`
- **Database persistence** is a separate package: `adk_ex_ecto` at `/workspace/adk_ex_ecto/` (keeps core lightweight)

### Critical Gotchas

1. **Compile order**: Define nested/referenced modules BEFORE parent modules in the same file (e.g., `Event.Actions` before `Event`)
2. **MapSet + dialyzer**: Avoid `MapSet` — use `%{key => true}` maps + `Map.has_key?/2` instead
3. **Credo nesting**: Max depth 2 — extract inner logic into helper functions
4. **Mock model**: Use `Mock.new(responses: [...])` NOT bare `%Mock{}` — needs Agent process for state
5. **Behaviour dispatch**: `ADK.Agent` has NO module functions — call `agent.__struct__.run(agent, ctx)` or the implementing module directly
6. **Test module names**: Use unique names to avoid cross-file collisions
7. **OTel span testing**: Use `otel_simple_processor.set_exporter(:otel_exporter_pid, self())` in setup. Span name is at `elem(span, 6)` (not 2) in the Erlang span record. Must restart opentelemetry app with proper processor config.
8. **Dialyzer unreachable branches**: If a function always returns `{:ok, _}`, don't pattern match `{:error, _}` — dialyzer flags it
9. **FunctionTool field**: Use `handler:` not `function:` in `FunctionTool.new/1`
10. **Plugin nil safety**: All `Plugin.Manager.run_*` functions accept `nil` as first arg — no nil checks needed at call sites
11. **SQLite in-memory testing**: Don't use Ecto sandbox with pool_size 1. Clean tables in setup instead.

---

## 6. Development Workflow

### Running Tests
```bash
cd /workspace/adk_ex
mix test                                        # Run all unit tests (240)
mix test test/integration/ --include integration # Run integration tests
mix test --trace                                 # Run with verbose output
mix credo                                        # Static analysis
mix dialyzer                                     # Type checking
```

### Conventions
- Module names: `ADK.Component.SubComponent` (e.g., `ADK.Agent.LlmAgent`)
- Behaviours: Define in dedicated files (e.g., `agent.ex`, `model.ex`, `tool.ex`)
- Structs: `defstruct` + `@type t :: %__MODULE__{}` typespecs
- Callbacks: Return `{value | nil, context}` — nil = continue, non-nil = short-circuit
- Errors: `{:ok, result}` / `{:error, reason}` tuples
- Tests: Mirror `lib/` structure under `test/`; use `async: true` unless shared state
- Use `Mock.new(responses: [...])` for test models
- Verify all changes: `mix test && mix credo && mix dialyzer`

---

## 7. Quick Commands

```bash
cd /workspace/adk_ex
mix test           # Run tests
mix credo          # Static analysis
mix dialyzer       # Type checking
iex -S mix         # Interactive shell
mix clean && mix compile  # Clean build
```

---

## 8. Key Contacts / Context

- **Project owner**: John Small (jds340@gmail.com)
- **ADK Elixir project**: `/workspace/adk_ex/` (github.com/JohnSmall/adk_ex)
- **A2A Elixir project**: `/workspace/a2a_ex/` (github.com/JohnSmall/a2a_ex)
- **Original AgentHub project**: `/workspace/agent_hub/` (predates ADK alignment)
