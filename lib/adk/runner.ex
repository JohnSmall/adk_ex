defmodule ADK.Runner do
  @moduledoc """
  Orchestrates agent execution within a session.

  The Runner manages session lifecycle, creates invocation contexts,
  runs agents, and persists events to the session service.
  """

  alias ADK.Agent.InvocationContext
  alias ADK.Agent.Tree
  alias ADK.Event
  alias ADK.Session
  alias ADK.Types
  alias ADK.Types.Content

  @type t :: %__MODULE__{
          app_name: String.t(),
          root_agent: struct(),
          session_service: GenServer.server(),
          artifact_service: term(),
          memory_service: term(),
          parent_map: %{String.t() => struct()}
        }

  @enforce_keys [:app_name, :root_agent, :session_service]
  defstruct [
    :app_name,
    :root_agent,
    :session_service,
    :artifact_service,
    :memory_service,
    parent_map: %{}
  ]

  @doc """
  Creates a new runner, validating the agent tree and building the parent map.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(opts) do
    root_agent = Keyword.fetch!(opts, :root_agent)

    case Tree.validate_unique_names(root_agent) do
      {:ok, _names} ->
        parent_map = Tree.build_parent_map(root_agent)

        runner = %__MODULE__{
          app_name: Keyword.fetch!(opts, :app_name),
          root_agent: root_agent,
          session_service: Keyword.fetch!(opts, :session_service),
          artifact_service: Keyword.get(opts, :artifact_service),
          memory_service: Keyword.get(opts, :memory_service),
          parent_map: parent_map
        }

        {:ok, runner}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Runs an agent with the given user message, returning a stream of events.

  Automatically creates a session if one doesn't exist.
  """
  @spec run(t(), String.t(), String.t(), Content.t(), keyword()) :: Enumerable.t()
  def run(%__MODULE__{} = runner, user_id, session_id, %Content{} = user_content, opts \\ []) do
    Stream.resource(
      fn -> init_run(runner, user_id, session_id, user_content, opts) end,
      &run_next/1,
      fn _ -> :ok end
    )
  end

  defp init_run(runner, user_id, session_id, user_content, opts) do
    session = get_or_create_session(runner, user_id, session_id)
    agent = find_agent_to_run(runner, session, user_content)
    run_config = Keyword.get(opts, :run_config, %ADK.RunConfig{})
    invocation_id = UUID.uuid4()

    ctx = %InvocationContext{
      agent: agent,
      session: session,
      invocation_id: invocation_id,
      user_content: user_content,
      run_config: run_config,
      session_service: runner.session_service,
      artifact_service: runner.artifact_service,
      memory_service: runner.memory_service,
      parent_map: runner.parent_map,
      root_agent: runner.root_agent
    }

    # Create user message event and commit it
    user_event =
      Event.new(
        invocation_id: invocation_id,
        author: "user",
        content: user_content
      )

    commit_event(runner, session, user_event)
    updated_session = append_event_to_session(session, user_event)
    ctx = %{ctx | session: updated_session}

    # Get the agent's event stream
    agent_stream = agent.__struct__.run(agent, ctx)
    events = Enum.to_list(agent_stream)

    {:events, events, runner, updated_session}
  end

  defp run_next({:events, [], _runner, _session}), do: {:halt, :done}

  defp run_next({:events, [event | rest], runner, session}) do
    # Commit non-partial events
    unless event.partial do
      commit_event(runner, session, event)
    end

    updated_session =
      if event.partial do
        session
      else
        append_event_to_session(session, event)
      end

    {[event], {:events, rest, runner, updated_session}}
  end

  defp get_or_create_session(runner, user_id, session_id) do
    svc = runner.session_service

    case ADK.Session.InMemory.get(svc, app_name: runner.app_name, user_id: user_id, session_id: session_id) do
      {:ok, session} ->
        session

      {:error, :not_found} ->
        {:ok, session} =
          ADK.Session.InMemory.create(svc,
            app_name: runner.app_name,
            user_id: user_id,
            session_id: session_id
          )

        session
    end
  end

  @doc false
  @spec find_agent_to_run(t(), Session.t(), Content.t()) :: struct()
  def find_agent_to_run(runner, session, user_content) do
    # If user message has function responses, find the agent that made the call
    if Types.has_function_responses?(user_content) do
      find_agent_for_function_responses(runner, session, user_content) ||
        find_last_active_agent(runner, session)
    else
      find_last_active_agent(runner, session)
    end
  end

  defp find_agent_for_function_responses(runner, session, user_content) do
    fr_ids =
      user_content
      |> Types.function_responses()
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)

    if fr_ids == [] do
      nil
    else
      session.events
      |> Enum.reverse()
      |> Enum.find_value(&match_fc_event(&1, fr_ids, runner))
    end
  end

  defp match_fc_event(event, fr_ids, runner) do
    if event.content && Types.has_function_calls?(event.content) && event.author do
      fc_ids = event.content |> Types.function_calls() |> Enum.map(& &1.id)
      has_match = Enum.any?(fr_ids, fn id -> id in fc_ids end)

      if has_match, do: resolve_agent(runner, event.author), else: nil
    end
  end

  defp find_last_active_agent(runner, session) do
    agent =
      session.events
      |> Enum.reverse()
      |> Enum.find_value(&resolve_active_agent(&1, runner))

    agent || runner.root_agent
  end

  defp resolve_active_agent(event, runner) do
    cond do
      is_binary(event.actions.transfer_to_agent) ->
        resolve_agent(runner, event.actions.transfer_to_agent)

      event.author && event.author != "user" ->
        resolve_agent(runner, event.author)

      true ->
        nil
    end
  end

  defp resolve_agent(runner, author) do
    case Tree.find_agent(runner.root_agent, author) do
      {:ok, agent} -> agent
      :error -> nil
    end
  end

  defp commit_event(runner, session, event) do
    ADK.Session.InMemory.append_event(runner.session_service, session, event)
  end

  defp append_event_to_session(session, event) do
    %{session | events: session.events ++ [event]}
  end
end
