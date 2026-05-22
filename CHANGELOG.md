# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-05-11

### Added

- `extra_headers` field on `ADK.Model.Claude`, `ADK.Model.Gemini`, and
  `ADK.Model.LiteLlm` — a list of `{name, value}` tuples appended after each
  provider's required headers. Enables sending `anthropic-beta`, custom
  tracing headers, or any other provider-specific header without forking the
  library. Defaults to `[]`.
- `receive_timeout` field on all three providers — HTTP receive timeout in
  milliseconds, replacing the previously hard-coded `120_000`. Defaults to
  `120_000` (unchanged behaviour for existing callers).
- `ADK.Model.Registry.resolve/2` now forwards `:extra_headers` and
  `:receive_timeout` opts to all provider branches (Gemini, Claude, DeepSeek,
  OpenAI/LiteLlm, slash-namespaced).
- `ADK.Model.Claude`, `Gemini`, and `LiteLlm` each expose a `build_headers/1`
  function (`@doc false`) for testability.
- `test/adk/model/claude_test.exs` — 10 unit tests for struct defaults and
  header building.
- `test/adk/model/gemini_test.exs` — 8 unit tests for struct defaults and
  header building.
- Additional `build_headers` and struct default tests in `lite_llm_test.exs`
  and `registry_test.exs`.
- DeepSeek model name resolution (`deepseek-*` → `ADK.Model.Claude` with
  `base_url: "https://api.deepseek.com/anthropic/v1"`).

## [1.1.0] - 2026-04-21

### Added

- `ADK.Model.LiteLlm` provider — generic OpenAI-compatible client that mirrors
  Google Python ADK's `LiteLlm(model="openai/gpt-4o")` pattern. Speaks the
  OpenAI Chat Completions wire format, so it works against OpenAI directly,
  a [LiteLLM proxy](https://docs.litellm.ai/) (which fronts 100+ providers
  under the same protocol), or any OpenAI-compatible endpoint (Groq, Together,
  OpenRouter, Ollama, vLLM, Azure OpenAI, LM Studio, etc.). Full function
  calling support via the `tools` parameter.
- `ADK.Model.Registry` now resolves `gpt-*`, `o1*`, and `o3*` model names to
  `LiteLlm` configured for OpenAI, and resolves any slash-namespaced model
  name (e.g. `"openai/gpt-4o"`, `"anthropic/claude-3-5-sonnet-20241022"`) to
  `LiteLlm` for LiteLLM-proxy routing (requires `:base_url`).
- `test/adk/model/lite_llm_test.exs` — 21 unit tests covering request
  serialization, tool handling, config passthrough, and response parsing.
- `test/adk/model/registry_test.exs` — 12 unit tests covering all provider
  prefixes (Gemini, Claude, OpenAI, LiteLLM proxy, unknown).
- `test/integration/openai_test.exs` — 2 integration tests against OpenAI
  (excluded by default; run with `OPENAI_API_KEY` set).
- `examples/openai.exs` — runnable example showing OpenAI via `LiteLlm`.
- `usage-rules/models.md` — LLM usage rule for provider selection and the
  LiteLLM pattern.

### Changed

- Docs (README, CLAUDE.md, architecture, onboarding, PRD, implementation plan,
  usage rules) updated to list OpenAI alongside Gemini and Claude.

## [1.0.0] - 2026-04-16

First public release on hex.pm.

## [0.2.1] - 2026-04-16

### Added

- Hex.pm package metadata (description, licenses, links, docs config)
- LICENSE file (MIT)
- CHANGELOG.md
- LLM usage-rules with sub-rule files (agents, tools, sessions, plugins, telemetry)
- Architecture and onboarding guides as ex_doc extras

### Changed

- README: added hex badges, usage_rules section, absolute URLs for hexdocs compatibility
- Cleaned all internal workspace paths from documentation for public release

## [0.2.0] - 2026-04-11

### Added

- Phase 5: Plugin system with 12 callback hooks (Runner/Agent/Model/Tool level)
- Plugin.Manager for chaining plugins with short-circuit semantics
- Toolset behaviour for dynamic tool providers
- Pluggable session backends via `session_module` on Runner
- OpenTelemetry included in all environments (previously dev/test only)

## [0.1.0] - 2026-03-15

### Added

- Phase 1: Core types (Content, Part, FunctionCall, FunctionResponse), Event system, Session management with prefix-scoped state, Agent behaviour and tree utilities
- Phase 2: Runner with session lifecycle, Flow state machine (Stream.resource/3), Tool system (FunctionTool, Tool.Context), LLM abstraction with Gemini and Claude providers, Model Registry
- Phase 3: Orchestration agents (LoopAgent, SequentialAgent, ParallelAgent), Agent transfer via TransferToAgent tool, Branch isolation for parallel execution
- Phase 4: Memory service with word-based search, Artifact service with versioned storage, Dual telemetry (OpenTelemetry spans + Elixir :telemetry events)
