# ADK Ex: Telemetry

ADK Ex emits dual telemetry: **OpenTelemetry spans** for distributed tracing and **Elixir `:telemetry` events** for metrics/logging.

## Elixir :telemetry Events

All events use the `[:adk_ex, ...]` prefix (not `[:adk, ...]`).

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:adk_ex, :llm, :start]` | `%{system_time: ...}` | `%{model: ..., agent_name: ...}` |
| `[:adk_ex, :llm, :stop]` | `%{duration: ...}` | `%{model: ..., agent_name: ...}` |
| `[:adk_ex, :llm, :exception]` | `%{duration: ...}` | `%{kind: ..., reason: ..., stacktrace: ...}` |
| `[:adk_ex, :tool, :start]` | `%{system_time: ...}` | `%{tool_name: ..., agent_name: ...}` |
| `[:adk_ex, :tool, :stop]` | `%{duration: ...}` | `%{tool_name: ..., agent_name: ...}` |
| `[:adk_ex, :tool, :exception]` | `%{duration: ...}` | `%{kind: ..., reason: ..., stacktrace: ...}` |

### Attaching Handlers

```elixir
:telemetry.attach_many(
  "my-handler",
  [
    [:adk_ex, :llm, :start],
    [:adk_ex, :llm, :stop],
    [:adk_ex, :tool, :start],
    [:adk_ex, :tool, :stop]
  ],
  &MyHandler.handle_event/4,
  nil
)
```

## OpenTelemetry Spans

ADK Ex creates OTel spans for LLM calls and tool executions:

| Span Name | Created By |
|-----------|-----------|
| `"call_llm"` | `ADK.Telemetry.span_llm_call/2` |
| `"execute_tool {name}"` | `ADK.Telemetry.span_tool_call/2` |
| `"execute_tool (merged)"` | `ADK.Telemetry.span_merged_tools/1` |

### Functions

```elixir
ADK.Telemetry.span_llm_call(%{model: "gemini-2.0-flash", agent: "my-agent"}, fn ->
  # ... LLM call ...
  {:ok, response}
end)

ADK.Telemetry.span_tool_call(%{tool_name: "search", agent: "my-agent"}, fn ->
  # ... tool execution ...
  {:ok, result}
end)
```

## Testing OTel Spans

The test configuration uses `otel_simple_processor` with a pid exporter.

### Setup in config/test.exs

```elixir
config :opentelemetry,
  traces_exporter: :none,
  processors: [{:otel_simple_processor, %{}}]
```

### In Tests

```elixir
setup do
  :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
  :ok
end

test "emits LLM span" do
  # ... trigger an LLM call ...

  assert_receive {:span, span}, 5000
  # Span name is at index 6 in the span tuple
  assert elem(span, 6) == "call_llm"
end
```

**Important**: Span name is `elem(span, 6)`, not `elem(span, 2)`. No application restart is needed between tests.

## Rules

1. **Prefix is `[:adk_ex, ...]`** — the package was renamed from `adk` to `adk_ex`. Do not use `[:adk, ...]`.
2. OTel spans are only created if the `:opentelemetry` dependency is available at runtime.
3. In tests, call `:otel_simple_processor.set_exporter(:otel_exporter_pid, self())` in setup — do not restart the OTel application.
4. Span tuples are Erlang records — use `elem(span, 6)` for the span name, not pattern matching on position 2.
5. The `:opentelemetry` dep must NOT have `only: [:dev, :test]` — it's needed at compile time in all environments.
