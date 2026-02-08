# ADK Ex

Elixir/OTP port of [Google's Agent Development Kit (ADK)](https://google.github.io/adk-docs/). Provides agent orchestration, session management, tool use, LLM abstraction, memory, artifacts, and telemetry.

## Features

- **Agent types**: LLM agents, Sequential, Parallel, Loop, and Custom agents
- **Tool system**: Function tools, agent transfer, memory search, artifact loading
- **Multi-LLM**: Gemini and Claude providers via REST API, extensible via behaviour
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
    {:adk_ex, "~> 0.1.0"}
  ]
end
```

For database-backed session persistence, add the separate `adk_ex_ecto` package (coming soon).

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

## Documentation

- [HexDocs](https://hexdocs.pm/adk_ex)
- [Google ADK Docs](https://google.github.io/adk-docs/) (reference)
- [Architecture](docs/architecture.md)

## Related Packages

- [`a2a_ex`](https://github.com/JohnSmall/a2a_ex) — A2A (Agent-to-Agent) protocol for Elixir, depends on this package

## License

MIT
