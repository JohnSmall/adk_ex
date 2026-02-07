defmodule ADK.Model.MockTest do
  use ExUnit.Case, async: true

  alias ADK.Model
  alias ADK.Model.{LlmRequest, LlmResponse, Mock}
  alias ADK.Types.Content

  test "name returns model_name" do
    model = Mock.new(model_name: "test-mock")
    assert Model.name(model) == "test-mock"
  end

  test "default name" do
    model = Mock.new()
    assert Model.name(model) == "mock-model"
  end

  test "returns default response when list empty" do
    model = Mock.new()
    request = %LlmRequest{}

    [response] = Model.generate_content(model, request, false)

    assert response.content.role == "model"
    assert hd(response.content.parts).text == "Mock response"
    assert response.turn_complete == true
  end

  test "returns responses in sequence" do
    r1 = %LlmResponse{content: Content.new_from_text("model", "First"), turn_complete: true}
    r2 = %LlmResponse{content: Content.new_from_text("model", "Second"), turn_complete: true}

    model = Mock.new(responses: [r1, r2])
    request = %LlmRequest{}

    [resp1] = Model.generate_content(model, request, false)
    assert hd(resp1.content.parts).text == "First"

    [resp2] = Model.generate_content(model, request, false)
    assert hd(resp2.content.parts).text == "Second"
  end

  test "supports function responses" do
    response_fn = fn %LlmRequest{} = req ->
      text = "You asked about: #{length(req.contents)} messages"
      %LlmResponse{content: Content.new_from_text("model", text), turn_complete: true}
    end

    model = Mock.new(responses: [response_fn])
    request = %LlmRequest{contents: [Content.new_from_text("user", "Hi")]}

    [response] = Model.generate_content(model, request, false)
    assert hd(response.content.parts).text == "You asked about: 1 messages"
  end

  test "falls back to default after list exhausted" do
    r1 = %LlmResponse{content: Content.new_from_text("model", "Only one"), turn_complete: true}
    model = Mock.new(responses: [r1])

    [_] = Model.generate_content(model, %LlmRequest{}, false)
    [resp] = Model.generate_content(model, %LlmRequest{}, false)

    assert hd(resp.content.parts).text == "Mock response"
  end

  test "pop_response works with struct-only mock" do
    r1 = %LlmResponse{content: Content.new_from_text("model", "One"), turn_complete: true}
    model = %Mock{responses: [r1]}

    {resp, model2} = Mock.pop_response(model, %LlmRequest{})
    assert hd(resp.content.parts).text == "One"

    {resp2, _model3} = Mock.pop_response(model2, %LlmRequest{})
    assert hd(resp2.content.parts).text == "Mock response"
  end
end
