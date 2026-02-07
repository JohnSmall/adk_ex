defmodule ADK.Model.LlmResponseTest do
  use ExUnit.Case, async: true

  alias ADK.Model.LlmResponse
  alias ADK.Types.Content

  test "default struct values" do
    resp = %LlmResponse{}
    assert resp.content == nil
    assert resp.partial == false
    assert resp.turn_complete == false
    assert resp.interrupted == false
    assert resp.error_code == nil
  end

  test "creates response with content" do
    content = Content.new_from_text("model", "Hello!")

    resp = %LlmResponse{
      content: content,
      turn_complete: true,
      finish_reason: "STOP"
    }

    assert resp.content.role == "model"
    assert resp.turn_complete == true
    assert resp.finish_reason == "STOP"
  end

  test "error response" do
    resp = %LlmResponse{
      error_code: "rate_limit",
      error_message: "Too many requests",
      turn_complete: true
    }

    assert resp.error_code == "rate_limit"
    assert resp.content == nil
  end

  test "streaming partial response" do
    resp = %LlmResponse{
      content: Content.new_from_text("model", "Hel"),
      partial: true,
      turn_complete: false
    }

    assert resp.partial == true
    assert resp.turn_complete == false
  end
end
