defmodule ADK.Model.LlmRequest do
  @moduledoc """
  Request to a model's generate_content call.

  `config` is a plain map for provider-specific settings (temperature, top_p, etc.).
  `tools` maps tool name to tool struct for O(1) lookup during function call handling.
  """

  alias ADK.Types.Content

  @type t :: %__MODULE__{
          model: String.t() | nil,
          system_instruction: Content.t() | nil,
          contents: [Content.t()],
          config: map(),
          tools: %{String.t() => struct()}
        }

  defstruct [
    :model,
    :system_instruction,
    contents: [],
    config: %{},
    tools: %{}
  ]
end
