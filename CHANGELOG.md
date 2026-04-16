# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
