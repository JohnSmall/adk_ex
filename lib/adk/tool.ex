defmodule ADK.Tool do
  @moduledoc """
  Behaviour for ADK tools.

  Tools are functions that agents can call during execution. Each tool
  provides a declaration (JSON Schema) for the LLM, and a `run/3` function
  for actual execution.
  """

  @doc "Returns the tool's unique name."
  @callback name(tool :: struct()) :: String.t()

  @doc "Returns a human-readable description of the tool."
  @callback description(tool :: struct()) :: String.t()

  @doc """
  Returns the tool's function declaration for the LLM.

  Returns a map with `"name"`, `"description"`, and `"parameters"` (JSON Schema).
  """
  @callback declaration(tool :: struct()) :: map()

  @doc """
  Executes the tool with the given context and arguments.

  Returns `{:ok, result_map}` on success or `{:error, reason}` on failure.
  """
  @callback run(tool :: struct(), context :: ADK.Tool.Context.t(), args :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc "Returns whether this tool is long-running (async)."
  @callback long_running?(tool :: struct()) :: boolean()

  @optional_callbacks long_running?: 1

  @doc "Calls `name/1` on any tool struct via its implementing module."
  @spec name(struct()) :: String.t()
  def name(tool), do: tool.__struct__.name(tool)

  @doc "Calls `description/1` on any tool struct via its implementing module."
  @spec description(struct()) :: String.t()
  def description(tool), do: tool.__struct__.description(tool)

  @doc "Calls `declaration/1` on any tool struct via its implementing module."
  @spec declaration(struct()) :: map()
  def declaration(tool), do: tool.__struct__.declaration(tool)

  @doc "Calls `run/3` on any tool struct via its implementing module."
  @spec run(struct(), ADK.Tool.Context.t(), map()) :: {:ok, map()} | {:error, term()}
  def run(tool, context, args), do: tool.__struct__.run(tool, context, args)

  @doc "Returns whether a tool is long-running."
  @spec long_running?(struct()) :: boolean()
  def long_running?(tool) do
    if function_exported?(tool.__struct__, :long_running?, 1) do
      tool.__struct__.long_running?(tool)
    else
      false
    end
  end
end
