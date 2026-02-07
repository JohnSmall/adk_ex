# Onboarding Guide: Elixir ADK Project

## For New AI Agents / Developers

This document provides everything needed to pick up the Elixir ADK project.

---

## 1. What Is This Project?

We are building an **Elixir/OTP port of Google's Agent Development Kit (ADK)** and the **Agent-to-Agent (A2A) protocol**. The Google ADK is a framework for building AI agents that can use tools, orchestrate sub-agents, manage sessions, and communicate with other agents.

Google provides the ADK in Python (reference), TypeScript, Go, and Java. We are creating the Elixir implementation.

---

## 2. Current Status

**Phase 1 (Foundation) and Phase 2 (Runner + Tool + LLM Agent) are COMPLETE.** The project lives at `/workspace/adk/`.

### What's Built

#### Phase 1: Foundation

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

#### Phase 2: Runner + Tool System + LLM Agent

| Module | Purpose | File |
|--------|---------|------|
| `ADK.Model` | Model behaviour (name/1, generate_content/3) | `lib/adk/model.ex` |
| `ADK.Model.LlmRequest` | LLM request struct (model, system_instruction, contents, config, tools) | `lib/adk/model/llm_request.ex` |
| `ADK.Model.LlmResponse` | LLM response struct (content, partial, turn_complete, error) | `lib/adk/model/llm_response.ex` |
| `ADK.Model.Mock` | Stateful mock model via Agent process (`Mock.new/1`) | `lib/adk/model/mock.ex` |
| `ADK.Model.Gemini` | Gemini REST API provider (Req) | `lib/adk/model/gemini.ex` |
| `ADK.Model.Claude` | Claude/Anthropic REST API provider (Req) | `lib/adk/model/claude.ex` |
| `ADK.Model.Registry` | Model name → provider resolution (gemini-*, claude-*) | `lib/adk/model/registry.ex` |
| `ADK.Tool` | Tool behaviour (name, description, declaration, run) | `lib/adk/tool.ex` |
| `ADK.Tool.Context` | Tool context with 3-level state delegation | `lib/adk/tool/context.ex` |
| `ADK.Tool.FunctionTool` | Anonymous function wrapper with try/rescue | `lib/adk/tool/function_tool.ex` |
| `ADK.Flow` | Flow engine (Stream.resource/3, max 25 iterations) | `lib/adk/flow.ex` |
| `ADK.Flow.Processors.Basic` | Copies generate_content_config into request | `lib/adk/flow/processors/basic.ex` |
| `ADK.Flow.Processors.ToolProcessor` | Populates tools map + function declarations | `lib/adk/flow/processors/tool_processor.ex` |
| `ADK.Flow.Processors.Instructions` | System instruction + {variable} interpolation | `lib/adk/flow/processors/instructions.ex` |
| `ADK.Flow.Processors.Contents` | Conversation history from session events | `lib/adk/flow/processors/contents.ex` |
| `ADK.Agent.LlmAgent` | LLM-powered agent (model, tools, callbacks, output_key) | `lib/adk/agent/llm_agent.ex` |
| `ADK.Runner` | Runner (session lifecycle, event persistence, agent routing) | `lib/adk/runner.ex` |

### Test Coverage
- 138 tests passing (75 Phase 1 + 63 Phase 2)
- 4 integration tests (Gemini + Claude, excluded by default)
- Credo: clean
- Dialyzer: clean

### What's Next
Phase 3: Orchestration Agents (SequentialAgent, ParallelAgent, LoopAgent) — see `docs/implementation-plan.md`

---

## 3. Key Resources

### Local Files

| Resource | Location |
|----------|----------|
| **This project (Elixir ADK)** | `/workspace/adk/` |
| **Google ADK Go source (PRIMARY ref)** | `/workspace/adk-go/` |
| **Google ADK Python source** | `/workspace/google-adk-venv/lib/python3.13/site-packages/google/adk/` |
| **A2A Go SDK** | `/workspace/a2a-go/` |
| **A2A samples** | `/workspace/a2a-samples/` |
| **PRD** | `/workspace/adk/docs/prd.md` |
| **Architecture** | `/workspace/adk/docs/architecture.md` |
| **Implementation plan** | `/workspace/adk/docs/implementation-plan.md` |
| **This guide** | `/workspace/adk/docs/onboarding.md` |
| **Project memory** | `/home/dev/.claude/projects/-workspace-agent-hub/memory/MEMORY.md` |

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
                  |                  |       |
                  |               [tool calls loop]
                  |                  |
               [commits events + state to Session]
                  |
               [yields Events to application]
```

### Execution Flow Detail

```
Runner.run/5
  ├── Get/create session from SessionService
  ├── Append user message event
  ├── Find agent to run (history scan or root)
  └── LlmAgent.run/2
        ├── [before_agent_callbacks] (may short-circuit)
        ├── Flow.run/2 (Stream.resource/3 loop)
        │     ├── Build LlmRequest via 4 processors:
        │     │     Basic → ToolProcessor → Instructions → Contents
        │     ├── [before_model_callbacks] (may short-circuit)
        │     ├── Model.generate_content/3 (Gemini/Claude/Mock)
        │     ├── [after_model_callbacks] (may replace)
        │     ├── If function_calls in response:
        │     │     [before_tool] → Tool.run/3 → [after_tool]
        │     │     Build tool response event → loop back to LLM
        │     └── If text response (final): emit event, halt
        ├── [after_agent_callbacks] (may short-circuit)
        └── If output_key: save text to state_delta
```

### Agent Types

| Type | Purpose | Status |
|------|---------|--------|
| CustomAgent | User-defined run function | Done (Phase 1) |
| LlmAgent | LLM-powered with tools | Done (Phase 2) |
| SequentialAgent | Run sub-agents in order | Phase 3 |
| ParallelAgent | Run sub-agents concurrently | Phase 3 |
| LoopAgent | Repeat sub-agents until termination | Phase 3 |

### 6 Callback Points

All callbacks return `{value | nil, updated_context}`. Nil = continue, non-nil = short-circuit.

| Hook | Signature | Short-circuit |
|------|-----------|---------------|
| before_agent | `(CallbackContext -> {Content \| nil, CallbackContext})` | Non-nil Content skips agent |
| after_agent | `(CallbackContext -> {Content \| nil, CallbackContext})` | Non-nil Content replaces output |
| before_model | `(CallbackContext, LlmRequest -> {LlmResponse \| nil, CallbackContext})` | Non-nil LlmResponse skips LLM |
| after_model | `(CallbackContext, LlmResponse -> {LlmResponse \| nil, CallbackContext})` | Non-nil LlmResponse replaces |
| before_tool | `(ToolContext, tool, args -> {map \| nil, ToolContext})` | Non-nil map skips tool |
| after_tool | `(ToolContext, tool, args, result -> {map \| nil, ToolContext})` | Non-nil map replaces result |

### State Prefixes

| Prefix | Scope | Persisted? |
|--------|-------|------------|
| (none) | Session-local | Yes |
| `app:` | Shared across all users/sessions | Yes |
| `user:` | Shared across user's sessions | Yes |
| `temp:` | Current invocation only | No (discarded) |

### State Delegation Chain (reads)

```
ToolContext.get_state(key)
  → check tool.actions.state_delta
  → check callback_context.actions.state_delta
  → check session.state
```

---

## 5. Project Structure

```
/workspace/adk/
  mix.exs                          # ADK.MixProject - deps: jason, elixir_uuid, req
  lib/
    adk.ex                         # Top-level module
    adk/
      application.ex               # OTP application (starts InMemory session)

      # === Phase 1: Foundation ===
      types.ex                     # Content, Part, FunctionCall, FunctionResponse, Blob
      event.ex                     # Event.Actions (first), then Event
      session.ex                   # Session struct
      run_config.ex                # RunConfig struct
      session/
        state.ex                   # State prefix utilities
        service.ex                 # Session.Service behaviour
        in_memory.ex               # InMemorySessionService (GenServer + ETS)
      agent.ex                     # Agent behaviour
      agent/
        config.ex                  # Agent.Config struct
        custom_agent.ex            # CustomAgent implementation
        invocation_context.ex      # InvocationContext (agent, session, services, parent_map, root_agent)
        callback_context.ex        # CallbackContext struct
        tree.ex                    # Agent tree utilities

      # === Phase 2: Runner + Tool + LLM Agent ===
      model.ex                     # Model behaviour (name/1, generate_content/3)
      model/
        llm_request.ex             # LlmRequest struct
        llm_response.ex            # LlmResponse struct
        mock.ex                    # Mock model (stateful via Agent process)
        gemini.ex                  # Gemini REST provider (Req)
        claude.ex                  # Claude REST provider (Req)
        registry.ex                # Model name → provider resolution
      tool.ex                      # Tool behaviour
      tool/
        context.ex                 # ToolContext struct
        function_tool.ex           # FunctionTool (anonymous function wrapper)
      flow.ex                      # Flow engine (Stream.resource/3, max 25 iterations)
      flow/
        processors/
          basic.ex                 # Config processor
          tool_processor.ex        # Tool declaration processor
          instructions.ex          # System instruction + {var} interpolation
          contents.ex              # Conversation history from session events
      agent/
        llm_agent.ex               # LlmAgent (model, tools, instruction, callbacks)
      runner.ex                    # Runner (session lifecycle, event persistence)

      # === Phase 3: Orchestration (NEXT) ===
      # agent/sequential_agent.ex  # Run sub-agents in order
      # agent/parallel_agent.ex    # Run sub-agents concurrently (Task.async_stream)
      # agent/loop_agent.ex        # Repeat until escalation/max_iterations

  test/
    test_helper.exs                # ExUnit.start(exclude: [:integration])
    adk/
      types_test.exs
      event_test.exs
      session/
        state_test.exs
        in_memory_test.exs
      agent/
        custom_agent_test.exs
        tree_test.exs
        llm_agent_test.exs         # 6 tests (name, run, tools, callbacks, output_key)
      model/
        llm_request_test.exs       # 3 tests
        llm_response_test.exs      # 4 tests
        mock_test.exs              # 7 tests (sequential, function_call, fallback)
      tool/
        function_tool_test.exs     # 8 tests
        context_test.exs           # 6 tests
      flow/
        processors/
          instructions_test.exs    # 7 tests
          contents_test.exs        # 7 tests
      flow_test.exs                # 8 tests (text, tools, callbacks, errors, max iter)
      runner_test.exs              # 6 tests (end-to-end, persist, tools, multi-turn)
    integration/
      gemini_test.exs              # @moduletag :integration (requires GEMINI_API_KEY)
      claude_test.exs              # @moduletag :integration (requires ANTHROPIC_API_KEY)
  docs/
    prd.md                         # Product Requirements Document
    architecture.md                # Detailed architecture document
    implementation-plan.md         # Phased TODO list
    onboarding.md                  # This file
```

---

## 6. Elixir/OTP Design Patterns Used

| ADK Concept | Elixir Equivalent | Why |
|-------------|-------------------|-----|
| BaseAgent (class) | `@behaviour` + struct | No inheritance in Elixir |
| Agent.Run() stream | `Stream.resource/3` | Lazy evaluation, yield/resume |
| Runner event loop | `Stream.resource/3` + init_run | Eagerly collects agent events, yields with session commits |
| Session storage | GenServer + 3 ETS tables | Serialized writes, concurrent reads |
| InvocationContext | Struct with all services | Threaded through agent tree |
| Async generators | `Enumerable.t()` (Stream) | Flow.run returns Stream of Events |
| Pydantic models | `defstruct` + `@type` | Typed structs with `@enforce_keys` |
| Tool execution | `tool.__struct__.run(tool, ctx, args)` | Dynamic dispatch via struct module |
| Model execution | `model.__struct__.generate_content(model, req, stream)` | Same pattern |
| Thread safety | GenServer `call` | Serialized access |

### Critical Compile-Order Rule

**Define nested/referenced modules BEFORE the modules that reference them in the same file.** For example, in `event.ex`:
- `ADK.Event.Actions` is defined FIRST
- `ADK.Event` is defined SECOND (because it references `%ADK.Event.Actions{}` in its default struct)

Similarly in `types.ex`, all sub-types (Blob, FunctionCall, etc.) are defined before `ADK.Types`.

### Mock Model Pattern

The Mock model uses an **Elixir Agent process** for stateful response tracking. Create with `Mock.new(responses: [...])` — NOT `%Mock{responses: [...]}`. Without the Agent process, the same response repeats infinitely in the Flow loop, causing 25 iterations before max_iterations halt.

### Behaviour vs Module Function Calls

`ADK.Agent` is a behaviour — it defines callbacks but NO module functions. You cannot call `ADK.Agent.run(agent, ctx)`. Instead, call the implementing module directly: `LlmAgent.run(agent, ctx)` or use dynamic dispatch: `agent.__struct__.run(agent, ctx)`.

### Dialyzer Gotcha: MapSet Opaque Types

Avoid using `MapSet` with `in` operator or `MapSet.member?/2` — dialyzer treats MapSet internals as opaque and will emit warnings. Use plain `%{key => true}` maps with `Map.has_key?/2` instead.

### Credo Nesting Depth

Credo enforces max nesting depth of 2. Extract deeply nested logic into separate private functions with pattern-matched clauses rather than nesting `case`/`if`/`cond` statements.

---

## 7. How to Reference Go ADK Source

The Go ADK is the primary reference for implementation. Key patterns to study:

```bash
# Agent interface and custom agent
cat /workspace/adk-go/agent/agent.go

# Session structs, Event, EventActions, State prefixes
cat /workspace/adk-go/session/session.go

# Session service interface
cat /workspace/adk-go/session/service.go

# InMemory session implementation
cat /workspace/adk-go/session/inmemory.go

# State utilities (ExtractStateDeltas, MergeStates)
cat /workspace/adk-go/internal/sessionutils/utils.go

# Context interfaces (InvocationContext, CallbackContext)
cat /workspace/adk-go/agent/context.go

# RunConfig
cat /workspace/adk-go/agent/run_config.go

# Runner
cat /workspace/adk-go/runner/runner.go

# LLM Agent + Flow
cat /workspace/adk-go/agent/llmagent/llmagent.go
cat /workspace/adk-go/internal/llminternal/base_flow.go

# Tools
cat /workspace/adk-go/tool/tool.go
cat /workspace/adk-go/tool/functiontool/function.go

# Orchestration agents (Phase 3 reference)
cat /workspace/adk-go/agent/sequentialagent/sequential_agent.go
cat /workspace/adk-go/agent/parallelagent/parallel_agent.go
cat /workspace/adk-go/agent/loopagent/loop_agent.go

# A2A integration (Phase 4 reference)
ls /workspace/adk-go/server/adka2a/
```

When implementing an Elixir module, always read the corresponding Go file first to understand:
1. The exact interface (methods, parameters, return types)
2. Edge cases handled
3. Error conditions
4. Integration points with other components

---

## 8. Development Workflow

### Running Tests
```bash
cd /workspace/adk
mix test                                        # Run all unit tests (138)
mix test test/integration/ --include integration # Run integration tests
mix test --trace                                # Run with verbose output
mix credo                                       # Static analysis
mix dialyzer                                    # Type checking (first run builds PLT)
```

### Starting a New Phase
1. Read the implementation plan section for the phase
2. Read the corresponding Go ADK source files
3. Create modules in compile-safe order (dependencies first)
4. Write tests alongside implementation
5. Check off tasks in `docs/implementation-plan.md`
6. Verify: `mix test && mix credo && mix dialyzer`

### Conventions
- Module names: `ADK.Component.SubComponent` (e.g., `ADK.Agent.LlmAgent`)
- Behaviours: Define in dedicated files (e.g., `agent.ex`, `model.ex`, `tool.ex`)
- Structs: `defstruct` + `@type t :: %__MODULE__{}` typespecs
- Callbacks: Return `{value | nil, context}` — nil = continue, non-nil = short-circuit
- Errors: `{:ok, result}` / `{:error, reason}` tuples
- Tests: Mirror `lib/` structure under `test/`
- All tests should be `async: true` unless they share state
- Use `Mock.new(responses: [...])` for test models (NOT bare struct)
- Use unique module names in tests to avoid cross-file collisions

---

## 9. Quick Commands

```bash
# Run tests
cd /workspace/adk && mix test

# Static analysis
mix credo

# Type checking
mix dialyzer

# Interactive shell
iex -S mix

# Clean build
mix clean && mix compile
```

---

## 10. Key Contacts / Context

- **Project owner**: John Small (jds340@gmail.com)
- **Original project**: AgentHub at `/workspace/agent_hub/` (predates ADK alignment)
- **ADK Elixir project**: `/workspace/adk/`
