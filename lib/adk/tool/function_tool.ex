defmodule ADK.Tool.FunctionTool do
  @moduledoc """
  A tool backed by an anonymous function.

  The simplest way to create a tool — provide a name, description,
  parameter schema, and a handler function.
  """

  @behaviour ADK.Tool

  alias ADK.Tool.Context

  @type handler :: (Context.t(), map() -> {:ok, map()} | {:error, term()})

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          handler: handler(),
          parameters: map(),
          is_long_running: boolean()
        }

  @enforce_keys [:name, :description, :handler]
  defstruct [:name, :description, :handler, parameters: %{}, is_long_running: false]

  @doc "Creates a new FunctionTool."
  @spec new(keyword()) :: t()
  def new(opts) do
    struct!(__MODULE__, opts)
  end

  @impl ADK.Tool
  def name(%__MODULE__{name: name}), do: name

  @impl ADK.Tool
  def description(%__MODULE__{description: desc}), do: desc

  @impl ADK.Tool
  def declaration(%__MODULE__{} = tool) do
    decl = %{
      "name" => tool.name,
      "description" => tool.description
    }

    if map_size(tool.parameters) > 0 do
      Map.put(decl, "parameters", tool.parameters)
    else
      decl
    end
  end

  @impl ADK.Tool
  def run(%__MODULE__{handler: handler}, %Context{} = context, args) do
    try do
      handler.(context, args)
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @impl ADK.Tool
  def long_running?(%__MODULE__{is_long_running: val}), do: val
end
