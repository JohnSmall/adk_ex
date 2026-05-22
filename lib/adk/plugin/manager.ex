defmodule ADK.Plugin.Manager do
  @moduledoc """
  Chains plugin callbacks. First non-nil return wins (short-circuit).

  All `run_*` functions accept `nil` as the first argument, acting as a
  no-op when no plugin manager is configured. This avoids nil checks at
  every call site.
  """

  alias ADK.Plugin

  @type t :: %__MODULE__{plugins: [Plugin.t()]}

  defstruct plugins: []

  @doc """
  Creates a new plugin manager from a list of plugins.

  Validates that plugin names are unique.
  """
  @spec new([Plugin.t()]) :: {:ok, t()} | {:error, String.t()}
  def new(plugins) do
    names = Enum.map(plugins, & &1.name)
    dupes = names -- Enum.uniq(names)

    if dupes == [] do
      {:ok, %__MODULE__{plugins: plugins}}
    else
      {:error, "Duplicate plugin names: #{Enum.join(Enum.uniq(dupes), ", ")}"}
    end
  end

  # -- Runner-level callbacks --

  @doc "Runs on_user_message plugins. May modify user content."
  def run_on_user_message(nil, ctx, _content), do: {nil, ctx}

  def run_on_user_message(%__MODULE__{} = mgr, ctx, content) do
    run_chain(mgr.plugins, :on_user_message, ctx, fn plugin, acc_ctx ->
      plugin.on_user_message.(acc_ctx, content)
    end)
  end

  @doc "Runs before_run plugins. May short-circuit with Content."
  def run_before_run(nil, ctx), do: {nil, ctx}

  def run_before_run(%__MODULE__{} = mgr, ctx) do
    run_chain(mgr.plugins, :before_run, ctx, fn plugin, acc_ctx ->
      plugin.before_run.(acc_ctx)
    end)
  end

  @doc "Runs after_run plugins. Notification only, no short-circuit."
  def run_after_run(nil, _ctx), do: :ok

  def run_after_run(%__MODULE__{} = mgr, ctx) do
    Enum.each(mgr.plugins, fn plugin ->
      if plugin.after_run, do: plugin.after_run.(ctx)
    end)

    :ok
  end

  @doc "Runs on_event plugins. May modify event."
  def run_on_event(nil, ctx, _event), do: {nil, ctx}

  def run_on_event(%__MODULE__{} = mgr, ctx, event) do
    run_chain(mgr.plugins, :on_event, ctx, fn plugin, acc_ctx ->
      plugin.on_event.(acc_ctx, event)
    end)
  end

  # -- Agent-level callbacks --

  @doc "Runs before_agent plugins. May short-circuit with Content."
  def run_before_agent(nil, cb_ctx), do: {nil, cb_ctx}

  def run_before_agent(%__MODULE__{} = mgr, cb_ctx) do
    run_chain(mgr.plugins, :before_agent, cb_ctx, fn plugin, acc_ctx ->
      plugin.before_agent.(acc_ctx)
    end)
  end

  @doc "Runs after_agent plugins. May replace output with Content."
  def run_after_agent(nil, cb_ctx), do: {nil, cb_ctx}

  def run_after_agent(%__MODULE__{} = mgr, cb_ctx) do
    run_chain(mgr.plugins, :after_agent, cb_ctx, fn plugin, acc_ctx ->
      plugin.after_agent.(acc_ctx)
    end)
  end

  # -- Model-level callbacks --

  @doc "Runs before_model plugins. May short-circuit with LlmResponse."
  def run_before_model(nil, cb_ctx, _request), do: {nil, cb_ctx}

  def run_before_model(%__MODULE__{} = mgr, cb_ctx, request) do
    run_chain(mgr.plugins, :before_model, cb_ctx, fn plugin, acc_ctx ->
      plugin.before_model.(acc_ctx, request)
    end)
  end

  @doc "Runs after_model plugins. May replace LlmResponse."
  def run_after_model(nil, cb_ctx, _response), do: {nil, cb_ctx}

  def run_after_model(%__MODULE__{} = mgr, cb_ctx, response) do
    run_chain(mgr.plugins, :after_model, cb_ctx, fn plugin, acc_ctx ->
      plugin.after_model.(acc_ctx, response)
    end)
  end

  @doc "Runs on_model_error plugins. May recover with LlmResponse."
  def run_on_model_error(nil, cb_ctx, _request, _error), do: {nil, cb_ctx}

  def run_on_model_error(%__MODULE__{} = mgr, cb_ctx, request, error) do
    run_chain(mgr.plugins, :on_model_error, cb_ctx, fn plugin, acc_ctx ->
      plugin.on_model_error.(acc_ctx, request, error)
    end)
  end

  # -- Tool-level callbacks --

  @doc "Runs before_tool plugins. May short-circuit with result map."
  def run_before_tool(nil, tool_ctx, _tool, _args), do: {nil, tool_ctx}

  def run_before_tool(%__MODULE__{} = mgr, tool_ctx, tool, args) do
    run_chain(mgr.plugins, :before_tool, tool_ctx, fn plugin, acc_ctx ->
      plugin.before_tool.(acc_ctx, tool, args)
    end)
  end

  @doc "Runs after_tool plugins. May replace result map."
  def run_after_tool(nil, tool_ctx, _tool, _args, _result), do: {nil, tool_ctx}

  def run_after_tool(%__MODULE__{} = mgr, tool_ctx, tool, args, result) do
    run_chain(mgr.plugins, :after_tool, tool_ctx, fn plugin, acc_ctx ->
      plugin.after_tool.(acc_ctx, tool, args, result)
    end)
  end

  @doc "Runs on_tool_error plugins. May recover with result map."
  def run_on_tool_error(nil, tool_ctx, _tool, _error), do: {nil, tool_ctx}

  def run_on_tool_error(%__MODULE__{} = mgr, tool_ctx, tool, error) do
    run_chain(mgr.plugins, :on_tool_error, tool_ctx, fn plugin, acc_ctx ->
      plugin.on_tool_error.(acc_ctx, tool, error)
    end)
  end

  # -- Internal --

  # Iterates plugins in order. For each plugin with a non-nil callback for
  # the given key, calls the callback function. First non-nil value wins.
  defp run_chain(plugins, callback_key, ctx, callback_fn) do
    Enum.reduce_while(plugins, {nil, ctx}, fn plugin, {_val, acc_ctx} ->
      if Map.get(plugin, callback_key) do
        apply_callback(callback_fn, plugin, acc_ctx)
      else
        {:cont, {nil, acc_ctx}}
      end
    end)
  end

  defp apply_callback(callback_fn, plugin, acc_ctx) do
    case callback_fn.(plugin, acc_ctx) do
      {nil, updated_ctx} -> {:cont, {nil, updated_ctx}}
      {value, updated_ctx} -> {:halt, {value, updated_ctx}}
    end
  end
end
