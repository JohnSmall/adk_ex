defmodule ADK.Model do
  @moduledoc """
  Behaviour for LLM model providers.

  Implementations wrap a specific LLM API (Gemini, Claude, etc.) and return
  streams of `LlmResponse` structs. When `stream: false`, the enumerable
  yields a single response. When `stream: true`, it yields partial chunks
  followed by a final response with `turn_complete: true`.
  """

  alias ADK.Model.LlmRequest

  @doc "Returns the model's identifier string."
  @callback name(model :: struct()) :: String.t()

  @doc """
  Generates content from the model.

  Returns an `Enumerable.t()` that yields `LlmResponse.t()` structs.
  """
  @callback generate_content(model :: struct(), request :: LlmRequest.t(), stream :: boolean()) ::
              Enumerable.t()

  @doc "Calls `name/1` on any model struct via its implementing module."
  @spec name(struct()) :: String.t()
  def name(model), do: model.__struct__.name(model)

  @doc "Calls `generate_content/3` on any model struct via its implementing module."
  @spec generate_content(struct(), LlmRequest.t(), boolean()) :: Enumerable.t()
  def generate_content(model, request, stream) do
    model.__struct__.generate_content(model, request, stream)
  end
end
