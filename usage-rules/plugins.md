# ADK Ex: Plugins

## Plugin Struct

Plugins hook into the Runner/Agent/Model/Tool lifecycle at 12 points.

```elixir
plugin = ADK.Plugin.new(
  name: "logging",
  before_model: fn request, ctx ->
    IO.inspect(request, label: "LLM request")
    {nil, ctx}
  end,
  after_model: fn response, ctx ->
    IO.inspect(response, label: "LLM response")
    {nil, ctx}
  end
)
```

## All 12 Callback Hooks

| Hook | When | Signature |
|------|------|-----------|
| `on_user_message` | User message received | `(content, ctx) -> {content \| nil, ctx}` |
| `before_run` | Before runner starts | `(ctx) -> {events \| nil, ctx}` |
| `after_run` | After runner completes | `(ctx) -> {events \| nil, ctx}` |
| `on_event` | Each event emitted | `(event, ctx) -> {event \| nil, ctx}` |
| `before_agent` | Before agent runs | `(ctx) -> {events \| nil, ctx}` |
| `after_agent` | After agent runs | `(ctx) -> {events \| nil, ctx}` |
| `before_model` | Before LLM call | `(request, ctx) -> {response \| nil, ctx}` |
| `after_model` | After LLM response | `(response, ctx) -> {response \| nil, ctx}` |
| `on_model_error` | LLM call failed | `(error, ctx) -> {response \| nil, ctx}` |
| `before_tool` | Before tool execution | `(tool, args, ctx) -> {result \| nil, ctx}` |
| `after_tool` | After tool execution | `(tool, args, result, ctx) -> {result \| nil, ctx}` |
| `on_tool_error` | Tool execution failed | `(tool, error, ctx) -> {result \| nil, ctx}` |

## Callback Return Convention

All callbacks return `{value | nil, updated_context}`:

- **Return `{nil, ctx}`** — continue to the next plugin, then to agent callbacks, then to the default behavior.
- **Return `{value, ctx}`** — short-circuit. The value is used directly; remaining plugins and agent callbacks are skipped.

## Plugin.Manager

Create a manager and pass it to the Runner:

```elixir
{:ok, manager} = ADK.Plugin.Manager.new([audit_plugin, cache_plugin])

{:ok, runner} = ADK.Runner.new(
  app_name: "my-app",
  root_agent: agent,
  session_service: service,
  plugins: [audit_plugin, cache_plugin]
)
```

## Execution Order

1. Plugins run **in list order** (first plugin in the list runs first).
2. Plugins run **before** agent callbacks at every hook point.
3. If any plugin returns non-nil, agent callbacks are **skipped entirely**.
4. All `Plugin.Manager.run_*` functions accept `nil` as the manager argument — they become no-ops. No nil guards needed.

## Example: Caching Plugin

```elixir
cache_plugin = ADK.Plugin.new(
  name: "cache",
  before_model: fn request, ctx ->
    case MyCache.get(request) do
      {:ok, cached} -> {cached, ctx}   # short-circuit LLM call
      :miss -> {nil, ctx}              # continue to LLM
    end
  end,
  after_model: fn response, ctx ->
    MyCache.put(ctx.last_request, response)
    {nil, ctx}  # don't short-circuit, just observe
  end
)
```

## Rules

1. Plugin `name` is required — it is used in error messages and debugging.
2. All callback fields are optional — omit hooks you don't need.
3. Never check if plugin_manager is nil before calling `Plugin.Manager.run_*` — it handles nil gracefully.
4. Plugin order matters — put short-circuiting plugins (like caches) before observing plugins (like loggers).
