# ADK Ex: Sessions

## Session Struct

```elixir
%ADK.Session{
  id: "session-1",
  app_name: "my-app",
  user_id: "user-1",
  state: %{},
  events: [],
  last_update_time: ~U[2026-01-01 00:00:00Z]
}
```

## Built-in: InMemory Service

ETS-backed session storage. Good for development and testing.

```elixir
# Start the service
{:ok, service} = ADK.Session.InMemory.start_link(name: :my_sessions)

# Create a session
{:ok, session} = ADK.Session.InMemory.create(service,
  app_name: "my-app",
  user_id: "user-1",
  session_id: "session-1",
  state: %{"lang" => "en"}
)

# Retrieve a session
{:ok, session} = ADK.Session.InMemory.get(service,
  app_name: "my-app",
  user_id: "user-1",
  session_id: "session-1"
)

# With options
{:ok, session} = ADK.Session.InMemory.get(service,
  app_name: "my-app",
  user_id: "user-1",
  session_id: "session-1",
  num_recent_events: 10,
  after: ~U[2026-01-01 00:00:00Z]
)
```

## State Prefixes

State keys use prefixes to control scope and persistence:

```elixir
# Session-local (no prefix) — scoped to this session
%{"counter" => 1}

# App-wide — shared across all sessions in the app
%{"app:global_config" => %{"theme" => "dark"}}

# User-wide — shared across all sessions for this user
%{"user:preferences" => %{"lang" => "en"}}

# Temporary — discarded after the current invocation
%{"temp:scratch" => "working data"}
```

Use `ADK.Session.State` to inspect scopes:

```elixir
ADK.Session.State.scope("counter")        # :session
ADK.Session.State.scope("app:config")     # :app
ADK.Session.State.scope("user:prefs")     # :user
ADK.Session.State.scope("temp:scratch")   # :temp
```

## Session.Service Behaviour

To implement a custom session backend:

```elixir
@callback create(server, keyword()) :: {:ok, Session.t()} | {:error, term()}
@callback get(server, keyword()) :: {:ok, Session.t()} | {:error, term()}
@callback append_event(server, Session.t(), Event.t()) :: {:ok, Event.t()} | {:error, term()}
@callback list_sessions(server, keyword()) :: {:ok, [Session.t()]} | {:error, term()}
@callback delete_session(server, keyword()) :: :ok | {:error, term()}
```

## Switching to Database Sessions

Use the `adk_ex_ecto` package for Ecto-backed persistence (SQLite3 dev, PostgreSQL prod):

```elixir
# In mix.exs
{:adk_ex_ecto, "~> 0.1"}

# In Runner
{:ok, runner} = ADK.Runner.new(
  app_name: "my-app",
  root_agent: agent,
  session_service: my_ecto_repo,
  session_module: ADKExEcto.SessionService
)
```

The `session_module` field on Runner controls which module handles session operations. It defaults to `ADK.Session.InMemory`.

## Rules

1. Session IDs are strings, not atoms.
2. State keys are always strings — use string keys in maps, not atoms.
3. `temp:` prefixed state is discarded after each `Runner.run/4` invocation — do not rely on it persisting.
4. `app:` and `user:` state deltas are extracted and persisted separately — use `ADK.Session.State.extract_deltas/1` to split them.
5. When testing with InMemory, you can pass `table_prefix:` to `start_link/1` to isolate test data.
