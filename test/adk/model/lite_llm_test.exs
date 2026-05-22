defmodule ADK.Model.LiteLlmTest do
  use ExUnit.Case, async: true

  alias ADK.Model
  alias ADK.Model.{LiteLlm, LlmRequest}
  alias ADK.Tool.FunctionTool
  alias ADK.Types.{Content, FunctionCall, FunctionResponse, Part}

  describe "name/1" do
    test "returns the configured model_name" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}
      assert Model.name(model) == "gpt-4o"
    end
  end

  describe "struct defaults" do
    test "defaults base_url to OpenAI" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}
      assert model.base_url == "https://api.openai.com/v1"
    end

    test "accepts overridden base_url" do
      model = %LiteLlm{
        model_name: "openai/gpt-4o",
        api_key: "sk-proxy",
        base_url: "http://localhost:4000"
      }

      assert model.base_url == "http://localhost:4000"
    end

    test "defaults extra_headers to empty list" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}
      assert model.extra_headers == []
    end

    test "defaults receive_timeout to 120_000" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}
      assert model.receive_timeout == 120_000
    end

    test "accepts custom extra_headers" do
      model = %LiteLlm{
        model_name: "gpt-4o",
        api_key: "sk-test",
        extra_headers: [{"x-custom", "value"}]
      }

      assert model.extra_headers == [{"x-custom", "value"}]
    end

    test "accepts custom receive_timeout" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test", receive_timeout: 60_000}
      assert model.receive_timeout == 60_000
    end
  end

  describe "build_headers/1" do
    test "includes required headers with default config" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}
      headers = LiteLlm.build_headers(model)

      assert {"authorization", "Bearer sk-test"} in headers
      assert {"content-type", "application/json"} in headers
    end

    test "appends extra_headers after required headers" do
      model = %LiteLlm{
        model_name: "gpt-4o",
        api_key: "sk-test",
        extra_headers: [{"x-custom", "val"}]
      }

      headers = LiteLlm.build_headers(model)

      assert [
               {"authorization", "Bearer sk-test"},
               {"content-type", "application/json"},
               {"x-custom", "val"}
             ] == headers
    end

    test "supports multiple extra headers" do
      model = %LiteLlm{
        model_name: "gpt-4o",
        api_key: "sk-test",
        extra_headers: [
          {"x-org-id", "org-123"},
          {"x-request-id", "req-456"}
        ]
      }

      headers = LiteLlm.build_headers(model)
      assert length(headers) == 4
      assert {"x-org-id", "org-123"} in headers
      assert {"x-request-id", "req-456"} in headers
    end

    test "empty extra_headers produces only required headers" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test", extra_headers: []}
      headers = LiteLlm.build_headers(model)
      assert length(headers) == 2
    end
  end

  describe "build_request_body/2 — messages" do
    test "sends only the model + messages when request is minimal" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}
      request = %LlmRequest{contents: [Content.new_from_text("user", "Hi")]}

      body = LiteLlm.build_request_body(model, request)

      assert body["model"] == "gpt-4o"
      assert body["messages"] == [%{"role" => "user", "content" => "Hi"}]
      refute Map.has_key?(body, "tools")
      refute Map.has_key?(body, "temperature")
    end

    test "prepends system instruction as a system message" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}

      request = %LlmRequest{
        system_instruction: Content.new_from_text("system", "Be brief."),
        contents: [Content.new_from_text("user", "Hi")]
      }

      body = LiteLlm.build_request_body(model, request)

      assert [
               %{"role" => "system", "content" => "Be brief."},
               %{"role" => "user", "content" => "Hi"}
             ] = body["messages"]
    end

    test "omits empty system instruction" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}

      request = %LlmRequest{
        system_instruction: Content.new_from_text("system", ""),
        contents: [Content.new_from_text("user", "Hi")]
      }

      body = LiteLlm.build_request_body(model, request)
      assert [%{"role" => "user", "content" => "Hi"}] = body["messages"]
    end

    test "maps role 'model' to 'assistant'" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}

      request = %LlmRequest{
        contents: [
          Content.new_from_text("user", "Hi"),
          Content.new_from_text("model", "Hello!")
        ]
      }

      body = LiteLlm.build_request_body(model, request)

      assert [
               %{"role" => "user", "content" => "Hi"},
               %{"role" => "assistant", "content" => "Hello!"}
             ] = body["messages"]
    end

    test "serializes assistant tool_calls from model content" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}

      call = %FunctionCall{name: "get_weather", id: "call_123", args: %{"city" => "Paris"}}
      assistant_content = %Content{role: "model", parts: [%Part{function_call: call}]}

      request = %LlmRequest{
        contents: [Content.new_from_text("user", "Weather?"), assistant_content]
      }

      body = LiteLlm.build_request_body(model, request)

      [_user_msg, assistant_msg] = body["messages"]
      assert assistant_msg["role"] == "assistant"
      assert assistant_msg["content"] == nil

      assert [
               %{
                 "id" => "call_123",
                 "type" => "function",
                 "function" => %{"name" => "get_weather", "arguments" => args_json}
               }
             ] = assistant_msg["tool_calls"]

      assert Jason.decode!(args_json) == %{"city" => "Paris"}
    end

    test "emits a tool role message for a function response" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}

      response = %FunctionResponse{
        name: "get_weather",
        id: "call_123",
        response: %{"temp" => "15C"}
      }

      tool_content = %Content{role: "model", parts: [%Part{function_response: response}]}

      request = %LlmRequest{
        contents: [Content.new_from_text("user", "Weather?"), tool_content]
      }

      body = LiteLlm.build_request_body(model, request)

      tool_msg = List.last(body["messages"])
      assert tool_msg["role"] == "tool"
      assert tool_msg["tool_call_id"] == "call_123"
      assert Jason.decode!(tool_msg["content"]) == %{"temp" => "15C"}
    end
  end

  describe "build_request_body/2 — tools" do
    test "serializes tools into OpenAI tools array" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}

      tool =
        FunctionTool.new(
          name: "get_weather",
          description: "Gets the weather",
          parameters: %{
            "type" => "object",
            "properties" => %{"city" => %{"type" => "string"}},
            "required" => ["city"]
          },
          handler: fn _ctx, _args -> {:ok, %{}} end
        )

      request = %LlmRequest{
        contents: [Content.new_from_text("user", "Hi")],
        tools: %{"get_weather" => tool}
      }

      body = LiteLlm.build_request_body(model, request)

      assert [
               %{
                 "type" => "function",
                 "function" => %{
                   "name" => "get_weather",
                   "description" => "Gets the weather",
                   "parameters" => %{
                     "type" => "object",
                     "properties" => %{"city" => %{"type" => "string"}},
                     "required" => ["city"]
                   }
                 }
               }
             ] = body["tools"]
    end

    test "omits tools when the tools map is empty" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}
      request = %LlmRequest{contents: [Content.new_from_text("user", "Hi")]}

      body = LiteLlm.build_request_body(model, request)
      refute Map.has_key?(body, "tools")
    end
  end

  describe "build_request_body/2 — config" do
    test "passes temperature, top_p, max_tokens, stop through" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}

      request = %LlmRequest{
        contents: [Content.new_from_text("user", "Hi")],
        config: %{
          "temperature" => 0.2,
          "top_p" => 0.9,
          "max_tokens" => 256,
          "stop" => ["\n\n"]
        }
      }

      body = LiteLlm.build_request_body(model, request)
      assert body["temperature"] == 0.2
      assert body["top_p"] == 0.9
      assert body["max_tokens"] == 256
      assert body["stop"] == ["\n\n"]
    end

    test "accepts Gemini-style config keys for cross-provider portability" do
      model = %LiteLlm{model_name: "gpt-4o", api_key: "sk-test"}

      request = %LlmRequest{
        contents: [Content.new_from_text("user", "Hi")],
        config: %{
          "topP" => 0.9,
          "maxOutputTokens" => 128,
          "stopSequences" => ["END"]
        }
      }

      body = LiteLlm.build_request_body(model, request)
      assert body["top_p"] == 0.9
      assert body["max_tokens"] == 128
      assert body["stop"] == ["END"]
    end
  end

  describe "parse_response/1" do
    test "parses a plain text response" do
      body = %{
        "choices" => [
          %{
            "message" => %{"role" => "assistant", "content" => "Hello!"},
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{"prompt_tokens" => 3, "completion_tokens" => 1, "total_tokens" => 4}
      }

      response = LiteLlm.parse_response(body)

      assert response.content.role == "model"
      assert [%Part{text: "Hello!"}] = response.content.parts
      assert response.finish_reason == "stop"
      assert response.usage_metadata["total_tokens"] == 4
      assert response.turn_complete
    end

    test "parses a tool_calls response" do
      body = %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_abc",
                  "type" => "function",
                  "function" => %{
                    "name" => "get_weather",
                    "arguments" => ~s({"city":"Paris"})
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }

      response = LiteLlm.parse_response(body)

      assert [%Part{function_call: %FunctionCall{} = fc}] = response.content.parts
      assert fc.name == "get_weather"
      assert fc.id == "call_abc"
      assert fc.args == %{"city" => "Paris"}
      assert response.finish_reason == "tool_calls"
    end

    test "parses text + tool_calls together" do
      body = %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "Looking that up...",
              "tool_calls" => [
                %{
                  "id" => "call_1",
                  "type" => "function",
                  "function" => %{"name" => "lookup", "arguments" => "{}"}
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }

      response = LiteLlm.parse_response(body)

      assert [%Part{text: "Looking that up..."}, %Part{function_call: fc}] =
               response.content.parts

      assert fc.name == "lookup"
      assert fc.args == %{}
    end

    test "returns error response when no choices" do
      response = LiteLlm.parse_response(%{"choices" => []})
      assert response.error_code == "no_choices"
      assert response.content == nil
      assert response.turn_complete
    end

    test "handles malformed tool arguments gracefully" do
      body = %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_bad",
                  "type" => "function",
                  "function" => %{"name" => "broken", "arguments" => "not-json"}
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }

      response = LiteLlm.parse_response(body)
      assert [%Part{function_call: fc}] = response.content.parts
      assert fc.args == %{"_raw" => "not-json"}
    end
  end
end
