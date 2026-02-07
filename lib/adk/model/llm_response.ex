defmodule ADK.Model.LlmResponse do
  @moduledoc """
  Response from a model's generate_content call.

  Fields mirror Google ADK's LlmResponse. When streaming, partial chunks
  have `partial: true` and the final chunk has `turn_complete: true`.
  """

  alias ADK.Types.Content

  @type t :: %__MODULE__{
          content: Content.t() | nil,
          error_code: String.t() | nil,
          error_message: String.t() | nil,
          finish_reason: String.t() | nil,
          usage_metadata: map() | nil,
          citation_metadata: map() | nil,
          grounding_metadata: map() | nil,
          custom_metadata: map() | nil,
          partial: boolean(),
          turn_complete: boolean(),
          interrupted: boolean()
        }

  defstruct [
    :content,
    :error_code,
    :error_message,
    :finish_reason,
    :usage_metadata,
    :citation_metadata,
    :grounding_metadata,
    :custom_metadata,
    partial: false,
    turn_complete: false,
    interrupted: false
  ]
end
