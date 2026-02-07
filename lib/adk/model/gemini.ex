defmodule ADK.Model.Gemini do
  @moduledoc """
  Google Gemini model provider.

  Calls the Gemini REST API (`generateContent` / `streamGenerateContent`).
  """

  @behaviour ADK.Model

  alias ADK.Model.{LlmRequest, LlmResponse}
  alias ADK.Types.{Content, FunctionCall, FunctionResponse, Part}

  @type t :: %__MODULE__{
          model_name: String.t(),
          api_key: String.t(),
          base_url: String.t()
        }

  @enforce_keys [:model_name, :api_key]
  defstruct [
    :model_name,
    :api_key,
    base_url: "https://generativelanguage.googleapis.com/v1beta"
  ]

  @impl ADK.Model
  def name(%__MODULE__{model_name: name}), do: name

  @impl ADK.Model
  def generate_content(%__MODULE__{} = model, %LlmRequest{} = request, _stream) do
    url = "#{model.base_url}/models/#{model.model_name}:generateContent"
    body = build_request_body(request)

    case Req.post(url, json: body, params: [key: model.api_key], receive_timeout: 120_000) do
      {:ok, %{status: 200, body: resp_body}} ->
        [parse_response(resp_body)]

      {:ok, %{status: status, body: resp_body}} ->
        [
          %LlmResponse{
            error_code: "http_#{status}",
            error_message: inspect(resp_body),
            turn_complete: true
          }
        ]

      {:error, reason} ->
        [
          %LlmResponse{
            error_code: "request_error",
            error_message: inspect(reason),
            turn_complete: true
          }
        ]
    end
  end

  @doc false
  @spec build_request_body(LlmRequest.t()) :: map()
  def build_request_body(%LlmRequest{} = request) do
    body = %{}

    body =
      if request.contents != [] do
        Map.put(body, "contents", Enum.map(request.contents, &serialize_content/1))
      else
        body
      end

    body =
      if request.system_instruction do
        Map.put(body, "systemInstruction", serialize_content(request.system_instruction))
      else
        body
      end

    body =
      case Map.get(request.config, "tools") do
        nil -> body
        tools -> Map.put(body, "tools", tools)
      end

    body =
      build_generation_config(request.config)
      |> then(fn
        config when map_size(config) > 0 -> Map.put(body, "generationConfig", config)
        _ -> body
      end)

    body
  end

  defp build_generation_config(config) do
    gen_keys = ["temperature", "topP", "topK", "maxOutputTokens", "stopSequences", "candidateCount"]

    Map.take(config, gen_keys)
  end

  @doc false
  def serialize_content(%Content{} = content) do
    %{
      "role" => gemini_role(content.role),
      "parts" => Enum.map(content.parts, &serialize_part/1)
    }
  end

  defp gemini_role("user"), do: "user"
  defp gemini_role("model"), do: "model"
  defp gemini_role(other), do: other

  defp serialize_part(%Part{text: text}) when is_binary(text) do
    %{"text" => text}
  end

  defp serialize_part(%Part{function_call: %FunctionCall{} = fc}) do
    %{
      "functionCall" => %{
        "name" => fc.name,
        "args" => fc.args
      }
    }
  end

  defp serialize_part(%Part{function_response: %FunctionResponse{} = fr}) do
    %{
      "functionResponse" => %{
        "name" => fr.name,
        "response" => fr.response
      }
    }
  end

  defp serialize_part(%Part{inline_data: %{data: data, mime_type: mime}}) do
    %{
      "inlineData" => %{
        "mimeType" => mime,
        "data" => Base.encode64(data)
      }
    }
  end

  defp serialize_part(_), do: %{}

  @doc false
  @spec parse_response(map()) :: LlmResponse.t()
  def parse_response(body) do
    candidates = Map.get(body, "candidates", [])

    case candidates do
      [candidate | _] ->
        content = parse_candidate_content(candidate)
        finish = Map.get(candidate, "finishReason")

        %LlmResponse{
          content: content,
          finish_reason: finish,
          turn_complete: true,
          usage_metadata: Map.get(body, "usageMetadata")
        }

      [] ->
        %LlmResponse{
          error_code: "no_candidates",
          error_message: "No candidates in response",
          turn_complete: true
        }
    end
  end

  defp parse_candidate_content(candidate) do
    case Map.get(candidate, "content") do
      nil ->
        nil

      content_map ->
        role = Map.get(content_map, "role", "model")
        parts = Map.get(content_map, "parts", []) |> Enum.map(&parse_part/1)
        %Content{role: role, parts: parts}
    end
  end

  defp parse_part(%{"text" => text}) do
    Part.new_text(text)
  end

  defp parse_part(%{"functionCall" => fc}) do
    %Part{
      function_call: %FunctionCall{
        name: Map.get(fc, "name"),
        args: Map.get(fc, "args", %{})
      }
    }
  end

  defp parse_part(%{"functionResponse" => fr}) do
    %Part{
      function_response: %FunctionResponse{
        name: Map.get(fr, "name"),
        response: Map.get(fr, "response", %{})
      }
    }
  end

  defp parse_part(_), do: Part.new_text("")
end
