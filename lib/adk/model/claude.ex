defmodule ADK.Model.Claude do
  @moduledoc """
  Anthropic Claude model provider.

  Calls the Claude Messages API with format conversion between ADK types
  and Anthropic's content block format.
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
    base_url: "https://api.anthropic.com/v1"
  ]

  @impl ADK.Model
  def name(%__MODULE__{model_name: name}), do: name

  @impl ADK.Model
  def generate_content(%__MODULE__{} = model, %LlmRequest{} = request, _stream) do
    url = "#{model.base_url}/messages"
    body = build_request_body(model, request)

    headers = [
      {"x-api-key", model.api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    case Req.post(url, json: body, headers: headers, receive_timeout: 120_000) do
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
  @spec build_request_body(t(), LlmRequest.t()) :: map()
  def build_request_body(%__MODULE__{} = model, %LlmRequest{} = request) do
    body = %{
      "model" => model.model_name,
      "max_tokens" => Map.get(request.config, "max_tokens", 4096),
      "messages" => build_messages(request.contents)
    }

    body =
      if request.system_instruction do
        text = extract_system_text(request.system_instruction)
        if text != "", do: Map.put(body, "system", text), else: body
      else
        body
      end

    body =
      case build_tools(request.tools) do
        [] -> body
        tools -> Map.put(body, "tools", tools)
      end

    # Add optional generation params
    body = maybe_put(body, "temperature", Map.get(request.config, "temperature"))
    body = maybe_put(body, "top_p", Map.get(request.config, "topP"))
    body = maybe_put(body, "top_k", Map.get(request.config, "topK"))
    body
  end

  defp build_messages(contents) do
    Enum.map(contents, &serialize_message/1)
  end

  defp serialize_message(%Content{role: role, parts: parts}) do
    %{
      "role" => claude_role(role),
      "content" => Enum.flat_map(parts, &serialize_part/1)
    }
  end

  defp claude_role("model"), do: "assistant"
  defp claude_role(other), do: other

  defp serialize_part(%Part{text: text}) when is_binary(text) do
    [%{"type" => "text", "text" => text}]
  end

  defp serialize_part(%Part{function_call: %FunctionCall{} = fc}) do
    [
      %{
        "type" => "tool_use",
        "id" => fc.id || "call_#{fc.name}",
        "name" => fc.name,
        "input" => fc.args
      }
    ]
  end

  defp serialize_part(%Part{function_response: %FunctionResponse{} = fr}) do
    [
      %{
        "type" => "tool_result",
        "tool_use_id" => fr.id || "call_#{fr.name}",
        "content" => Jason.encode!(fr.response)
      }
    ]
  end

  defp serialize_part(_), do: []

  defp build_tools(tools_map) when map_size(tools_map) == 0, do: []

  defp build_tools(tools_map) do
    Enum.map(tools_map, fn {_name, tool} ->
      decl = ADK.Tool.declaration(tool)

      tool_def = %{
        "name" => Map.get(decl, "name"),
        "description" => Map.get(decl, "description", "")
      }

      case Map.get(decl, "parameters") do
        nil -> tool_def
        params -> Map.put(tool_def, "input_schema", params)
      end
    end)
  end

  defp extract_system_text(%Content{parts: parts}) do
    parts
    |> Enum.map_join("", fn part ->
      if part.text, do: part.text, else: ""
    end)
  end

  @doc false
  @spec parse_response(map()) :: LlmResponse.t()
  def parse_response(body) do
    content_blocks = Map.get(body, "content", [])
    stop_reason = Map.get(body, "stop_reason")
    usage = Map.get(body, "usage")

    parts = Enum.map(content_blocks, &parse_content_block/1)

    content =
      if parts == [] do
        nil
      else
        %Content{role: "model", parts: parts}
      end

    %LlmResponse{
      content: content,
      finish_reason: stop_reason,
      turn_complete: true,
      usage_metadata: usage
    }
  end

  defp parse_content_block(%{"type" => "text", "text" => text}) do
    Part.new_text(text)
  end

  defp parse_content_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    %Part{
      function_call: %FunctionCall{
        name: name,
        id: id,
        args: input
      }
    }
  end

  defp parse_content_block(_), do: Part.new_text("")

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
