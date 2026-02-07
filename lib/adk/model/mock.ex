defmodule ADK.Model.Mock do
  @moduledoc """
  Mock model for testing without real API calls.

  Configured with a list of responses (either `LlmResponse` structs or
  functions that take an `LlmRequest` and return an `LlmResponse`).
  Returns them in sequence via an internal Agent process for statefulness.
  Falls back to a default text response if the list is exhausted.
  """

  @behaviour ADK.Model

  alias ADK.Model.{LlmRequest, LlmResponse}
  alias ADK.Types.Content

  @type response_fn :: (LlmRequest.t() -> LlmResponse.t())
  @type response_entry :: LlmResponse.t() | response_fn()

  @type t :: %__MODULE__{
          model_name: String.t(),
          responses: [response_entry()],
          pid: pid() | nil
        }

  @enforce_keys []
  defstruct model_name: "mock-model",
            responses: [],
            pid: nil

  @doc """
  Creates a new Mock model with an internal Agent for stateful response tracking.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    responses = Keyword.get(opts, :responses, [])
    model_name = Keyword.get(opts, :model_name, "mock-model")
    {:ok, pid} = Agent.start_link(fn -> responses end)
    %__MODULE__{model_name: model_name, responses: responses, pid: pid}
  end

  @impl ADK.Model
  def name(%__MODULE__{model_name: name}), do: name

  @impl ADK.Model
  def generate_content(%__MODULE__{pid: pid} = _model, %LlmRequest{} = request, _stream)
      when is_pid(pid) do
    response =
      Agent.get_and_update(pid, fn
        [] ->
          default = %LlmResponse{
            content: Content.new_from_text("model", "Mock response"),
            turn_complete: true
          }

          {default, []}

        [head | tail] ->
          resp =
            case head do
              %LlmResponse{} -> head
              fun when is_function(fun, 1) -> fun.(request)
            end

          {resp, tail}
      end)

    [response]
  end

  def generate_content(%__MODULE__{responses: responses} = _model, %LlmRequest{} = request, _stream) do
    # Fallback for struct-based mock without pid (backward compat)
    case responses do
      [] ->
        [%LlmResponse{content: Content.new_from_text("model", "Mock response"), turn_complete: true}]

      [head | _] ->
        resp =
          case head do
            %LlmResponse{} -> head
            fun when is_function(fun, 1) -> fun.(request)
          end

        [resp]
    end
  end

  @doc """
  Pops the next response from the model, returning {response, updated_model}.

  Useful for tests that need to track consumed responses.
  """
  @spec pop_response(t(), LlmRequest.t()) :: {LlmResponse.t(), t()}
  def pop_response(%__MODULE__{responses: []} = model, _request) do
    response = %LlmResponse{
      content: Content.new_from_text("model", "Mock response"),
      turn_complete: true
    }

    {response, model}
  end

  def pop_response(%__MODULE__{responses: [head | tail]} = model, request) do
    response =
      case head do
        %LlmResponse{} -> head
        fun when is_function(fun, 1) -> fun.(request)
      end

    {response, %{model | responses: tail}}
  end
end
