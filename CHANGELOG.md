# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
  `LiteLlm` configured for OpenAI, resolves any slash-namespaced model
  name (e.g. `"openai/gpt-4o"`, `"anthropic/claude-3-5-sonnet-20241022"`) to
  `LiteLlm` for LiteLLM-proxy routing (requires `:base_url`), and resolves
  `deepseek-*` model names to `Claude` configured for DeepSeek's
  Anthropic-compatible endpoint (`base_url: "https://api.deepseek.com/anthropic/v1"`).
- `test/adk/model/lite_llm_test.exs` — 21 unit tests covering request
  serialization, tool handling, config passthrough, and response parsing.
- `test/adk/model/registry_test.exs` — 15 unit tests covering all provider
  prefixes (Gemini, Claude, DeepSeek, OpenAI, LiteLLM proxy, unknown).
- `test/integration/openai_test.exs` — 2 integration tests against OpenAI
  (excluded by default; run with `OPENAI_API_KEY` set).
- `examples/openai.exs` — runnable example showing OpenAI via `LiteLlm`.
- `usage-rules/models.md` — LLM usage rule for provider selection and the
  LiteLLM pattern.

### Changed

- Docs (README, CLAUDE.md, architecture, onboarding, PRD, implementation plan,
  usage rules) updated to list OpenAI and DeepSeek alongside Gemini and Claude.

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
