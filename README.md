# ADK Ex

[![Hex.pm](https://img.shields.io/hexpm/v/adk_ex.svg)](https://hex.pm/packages/adk_ex)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/adk_ex)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Elixir/OTP port of [Google's Agent Development Kit (ADK)](https://google.github.io/adk-docs/). Provides agent orchestration, session management, tool use, LLM abstraction, memory, artifacts, and telemetry.

## Features

- **Agent types**: LLM agents, Sequential, Parallel, Loop, and Custom agents
- **Tool system**: Function tools, agent transfer, memory search, artifact loading
- **Multi-LLM**: Gemini, Claude, DeepSeek, and OpenAI (plus any OpenAI-compatible endpoint or LiteLLM proxy for 100+ providers), extensible via behaviour
- **Session management**: Prefix-scoped state (session/app/user/temp) with GenServer + ETS
- **Memory service**: Cross-session knowledge with word-based search
- **Artifact service**: Versioned file storage with user-scoped sharing
- **Telemetry**: Dual OpenTelemetry spans + Elixir `:telemetry` events
- **Orchestration**: Multi-agent workflows with agent transfer, escalation, and branch isolation

## Installation

Add `adk_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:adk_ex, "~> 1.0"}
  ]
end
```

For database-backed session persistence, add the separate [`adk_ex_ecto`](https://github.com/JohnSmall/adk_ex_ecto) package.

## Quick Example

```elixir
# Define a tool
tool = ADK.Tool.FunctionTool.new(
  name: "get_weather",
  description: "Get weather for a city",
  handler: fn _ctx, %{"city" => city} ->
    {:ok, %{"weather" => "Sunny in #{city}"}}
  end
)

# Create an LLM agent
agent = %ADK.Agent.LlmAgent{
  name: "weather-agent",
  model: ADK.Model.Registry.resolve("gemini-2.0-flash"),
  instruction: "You are a helpful weather assistant.",
  tools: [tool]
}

# Run
{:ok, runner} = ADK.Runner.new(
  app_name: "my-app",
  root_agent: agent,
  session_service: my_session_service
)

events =
  runner
  |> ADK.Runner.run("user-1", "session-1", ADK.Types.Content.new_from_text("user", "What's the weather in Paris?"))
  |> Enum.to_list()
```

## Using OpenAI (and other providers via LiteLLM)

Mirrors Google's Python ADK `LiteLlm(model="openai/gpt-4o")` pattern. `ADK.Model.LiteLlm` speaks the OpenAI Chat Completions wire format, which is also what the [LiteLLM proxy](https://docs.litellm.ai/) emulates for 100+ providers.

```elixir
# Direct OpenAI
model = %ADK.Model.LiteLlm{
  model_name: "gpt-4o",
  api_key: System.fetch_env!("OPENAI_API_KEY"),
  base_url: "https://api.openai.com/v1"
}

# Or via the registry:
{:ok, model} = ADK.Model.Registry.resolve("gpt-4o", api_key: api_key)

# Through a LiteLLM proxy (multi-provider routing):
model = %ADK.Model.LiteLlm{
  model_name: "anthropic/claude-3-5-sonnet-20241022",
  api_key: "sk-litellm-master-key",
  base_url: "http://localhost:4000"
}
```

See [`examples/openai.exs`](https://github.com/JohnSmall/adk_ex/blob/main/examples/openai.exs) for a complete runnable example.

## Using DeepSeek

DeepSeek's Anthropic-compatible API is supported via the registry:

```elixir
{:ok, model} = ADK.Model.Registry.resolve("deepseek-v4-pro", api_key: api_key)
```

## Custom Headers and Timeout

All providers accept `extra_headers` and `receive_timeout`:

```elixir
model = %ADK.Model.Claude{
  model_name: "claude-sonnet-4-5",
  api_key: api_key,
  extra_headers: [{"anthropic-beta", "prompt-caching-2024-07-31"}],
  receive_timeout: 180_000
}

# Or via the registry (works for all providers):
{:ok, model} = ADK.Model.Registry.resolve("claude-sonnet-4-5",
  api_key: api_key,
  extra_headers: [{"anthropic-beta", "prompt-caching-2024-07-31"}],
  receive_timeout: 180_000
)
```

## Documentation

- [HexDocs](https://hexdocs.pm/adk_ex)
- [Google ADK Docs](https://google.github.io/adk-docs/) (reference)
- [Architecture](https://github.com/JohnSmall/adk_ex/blob/main/docs/architecture.md)

## Related Packages

- [`a2a_ex`](https://github.com/JohnSmall/a2a_ex) — A2A (Agent-to-Agent) protocol for Elixir, depends on this package

## LLM Usage Rules

This package ships [usage rules](https://hexdocs.pm/usage_rules) for LLM-assisted development. Add to your app's `mix.exs`:

```elixir
# In project/0:
usage_rules: [file: "AGENTS.md", usage_rules: [:adk_ex]]

# In deps:
{:usage_rules, "~> 1.2", only: :dev}
```

Then run `mix usage_rules.sync` to pull ADK conventions into your `AGENTS.md` / `CLAUDE.md`.

## License

MIT — see [LICENSE](https://github.com/JohnSmall/adk_ex/blob/main/LICENSE) for details.
