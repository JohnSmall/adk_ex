defmodule ADK.Model.LlmRequestTest do
  use ExUnit.Case, async: true

  alias ADK.Model.LlmRequest
  alias ADK.Types.Content

  test "default struct values" do
    req = %LlmRequest{}
    assert req.model == nil
    assert req.system_instruction == nil
    assert req.contents == []
    assert req.config == %{}
    assert req.tools == %{}
  end

  test "creates request with fields" do
    content = Content.new_from_text("user", "Hello")

    req = %LlmRequest{
      model: "gemini-2.0-flash",
      contents: [content],
      config: %{"temperature" => 0.7}
    }

    assert req.model == "gemini-2.0-flash"
    assert length(req.contents) == 1
    assert req.config["temperature"] == 0.7
  end

  test "tools map for lookup" do
    req = %LlmRequest{
      tools: %{"get_weather" => :mock_tool, "search" => :mock_search}
    }

    assert Map.get(req.tools, "get_weather") == :mock_tool
    assert Map.get(req.tools, "missing") == nil
  end
end
