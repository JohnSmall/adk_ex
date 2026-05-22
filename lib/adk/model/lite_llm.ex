defmodule ADK.Model.LiteLlm do
  @moduledoc """
  Generic OpenAI-compatible model provider.

  Mirrors the `LiteLlm` wrapper class from Google's Python ADK. Speaks the
  OpenAI Chat Completions wire format (`POST /chat/completions`), which is
  also the format emulated by the [LiteLLM proxy](https://docs.litellm.ai/)
  and every OpenAI-compatible endpoint (Groq, Together, OpenRouter, Ollama,
  vLLM, LM Studio, Azure OpenAI, and 100+ others via LiteLLM).

  ## Usage

  ### Direct OpenAI

      %ADK.Model.LiteLlm{
        model_name: "gpt-4o",
        api_key: System.fetch_env!("OPENAI_API_KEY"),
        base_url: "https://api.openai.com/v1"
      }

  (Or resolve via `ADK.Model.Registry.resolve("gpt-4o", api_key: key)` — `gpt-*`,
  `o1*`, and `o3*` model names default to the OpenAI base URL.)

  ### Through a LiteLLM proxy

      %ADK.Model.LiteLlm{
        model_name: "openai/gpt-4o",
        api_key: "sk-litellm-master-key",
        base_url: "http://localhost:4000"
      }

  The proxy inspects the `provider/model` prefix to route to the correct
  upstream. Any model string LiteLLM recognizes works here (e.g.
  `"anthropic/claude-3-5-sonnet-20241022"`, `"ollama/llama3"`,
  `"groq/mixtral-8x7b-32768"`).

  ### Any OpenAI-compatible endpoint

      %ADK.Model.LiteLlm{
        model_name: "llama3",
        api_key: "none",
        base_url: "http://localhost:11434/v1"
      }

  ## Function calling

  Tools defined via `ADK.Tool.FunctionTool` are serialized to OpenAI's
  `tools: [{type: "function", function: {...}}]` schema. Assistant-emitted
  `tool_calls` are parsed back into `ADK.Types.FunctionCall` parts, and
  `ADK.Types.FunctionResponse` parts are serialized as `role: "tool"`
  messages with `tool_call_id`.
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
    base_url: "https://api.openai.com/v1"
  ]

  @impl ADK.Model
  def name(%__MODULE__{model_name: name}), do: name

  @impl ADK.Model
  def generate_content(%__MODULE__{} = model, %LlmRequest{} = request, _stream) do
    url = "#{model.base_url}/chat/completions"
    body = build_request_body(model, request)

    headers = [
      {"authorization", "Bearer #{model.api_key}"},
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
    messages = build_messages(request.system_instruction, request.contents)

    body = %{
      "model" => model.model_name,
      "messages" => messages
    }

    body =
      case build_tools(request.tools) do
        [] -> body
        tools -> Map.put(body, "tools", tools)
      end

    body
    |> maybe_put("temperature", Map.get(request.config, "temperature"))
    |> maybe_put("top_p", Map.get(request.config, "topP") || Map.get(request.config, "top_p"))
    |> maybe_put(
      "max_tokens",
      Map.get(request.config, "max_tokens") || Map.get(request.config, "maxOutputTokens")
    )
    |> maybe_put(
      "stop",
      Map.get(request.config, "stop") || Map.get(request.config, "stopSequences")
    )
  end

  defp build_messages(system_instruction, contents) do
    system_messages =
      case system_instruction do
        nil ->
          []

        %Content{} = c ->
          case extract_text(c) do
            "" -> []
            text -> [%{"role" => "system", "content" => text}]
          end
      end

    system_messages ++ Enum.flat_map(contents, &serialize_message/1)
  end

  defp serialize_message(%Content{role: "user", parts: parts}) do
    [%{"role" => "user", "content" => user_content(parts)}]
  end

  defp serialize_message(%Content{role: "model", parts: parts}) do
    text = collect_text(parts)
    tool_calls = collect_tool_calls(parts)

    message =
      %{"role" => "assistant"}
      |> Map.put("content", if(text == "", do: nil, else: text))
      |> maybe_put_tool_calls(tool_calls)

    tool_messages = collect_tool_response_messages(parts)

    [message | tool_messages]
  end

  defp serialize_message(%Content{role: role, parts: parts}) do
    [%{"role" => role, "content" => collect_text(parts)}]
  end

  defp user_content(parts) do
    text_only? = Enum.all?(parts, fn p -> not is_nil(p.text) end)

    if text_only? do
      collect_text(parts)
    else
      Enum.flat_map(parts, &serialize_user_part/1)
    end
  end

  defp serialize_user_part(%Part{text: text}) when is_binary(text) do
    [%{"type" => "text", "text" => text}]
  end

  defp serialize_user_part(%Part{inline_data: %{data: data, mime_type: mime}}) do
    [
      %{
        "type" => "image_url",
        "image_url" => %{"url" => "data:#{mime};base64,#{Base.encode64(data)}"}
      }
    ]
  end

  defp serialize_user_part(_), do: []

  defp collect_text(parts) do
    Enum.map_join(parts, "", fn p -> p.text || "" end)
  end

  defp collect_tool_calls(parts) do
    parts
    |> Enum.filter(& &1.function_call)
    |> Enum.map(fn %Part{function_call: %FunctionCall{} = fc} ->
      %{
        "id" => fc.id || "call_#{fc.name}",
        "type" => "function",
        "function" => %{
          "name" => fc.name,
          "arguments" => Jason.encode!(fc.args || %{})
        }
      }
    end)
  end

  defp collect_tool_response_messages(parts) do
    parts
    |> Enum.filter(& &1.function_response)
    |> Enum.map(fn %Part{function_response: %FunctionResponse{} = fr} ->
      %{
        "role" => "tool",
        "tool_call_id" => fr.id || "call_#{fr.name}",
        "content" => Jason.encode!(fr.response || %{})
      }
    end)
  end

  defp maybe_put_tool_calls(message, []), do: message
  defp maybe_put_tool_calls(message, calls), do: Map.put(message, "tool_calls", calls)

  defp build_tools(tools_map) when map_size(tools_map) == 0, do: []

  defp build_tools(tools_map) do
    Enum.map(tools_map, fn {_name, tool} ->
      decl = ADK.Tool.declaration(tool)

      function_def = %{
        "name" => Map.get(decl, "name"),
        "description" => Map.get(decl, "description", "")
      }

      function_def =
        case Map.get(decl, "parameters") do
          nil -> function_def
          params -> Map.put(function_def, "parameters", params)
        end

      %{"type" => "function", "function" => function_def}
    end)
  end

  defp extract_text(%Content{parts: parts}) do
    Enum.map_join(parts, "", fn p -> p.text || "" end)
  end

  @doc false
  @spec parse_response(map()) :: LlmResponse.t()
  def parse_response(body) do
    choices = Map.get(body, "choices", [])

    case choices do
      [choice | _] ->
        message = Map.get(choice, "message", %{})
        finish = Map.get(choice, "finish_reason")
        parts = parse_message_parts(message)

        content =
          if parts == [] do
            nil
          else
            %Content{role: "model", parts: parts}
          end

        %LlmResponse{
          content: content,
          finish_reason: finish,
          turn_complete: true,
          usage_metadata: Map.get(body, "usage")
        }

      [] ->
        %LlmResponse{
          error_code: "no_choices",
          error_message: "No choices in response",
          turn_complete: true
        }
    end
  end

  defp parse_message_parts(message) do
    text_parts =
      case Map.get(message, "content") do
        nil -> []
        "" -> []
        text when is_binary(text) -> [Part.new_text(text)]
        _ -> []
      end

    tool_parts =
      message
      |> Map.get("tool_calls", [])
      |> Enum.map(&parse_tool_call/1)

    text_parts ++ tool_parts
  end

  defp parse_tool_call(%{"id" => id, "function" => %{"name" => name} = fun}) do
    args =
      case Map.get(fun, "arguments") do
        nil -> %{}
        "" -> %{}
        raw when is_binary(raw) -> decode_args(raw)
        map when is_map(map) -> map
      end

    %Part{function_call: %FunctionCall{name: name, id: id, args: args}}
  end

  defp parse_tool_call(_), do: Part.new_text("")

  defp decode_args(raw) do
    case Jason.decode(raw) do
      {:ok, map} when is_map(map) -> map
      _ -> %{"_raw" => raw}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
