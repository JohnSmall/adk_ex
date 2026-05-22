defmodule ADK.Model.GeminiTest do
  use ExUnit.Case, async: true

  alias ADK.Model.Gemini

  describe "struct defaults" do
    test "defaults extra_headers to empty list" do
      model = %Gemini{model_name: "gemini-2.0-flash", api_key: "k"}
      assert model.extra_headers == []
    end

    test "defaults receive_timeout to 120_000" do
      model = %Gemini{model_name: "gemini-2.0-flash", api_key: "k"}
      assert model.receive_timeout == 120_000
    end

    test "accepts custom extra_headers" do
      model = %Gemini{
        model_name: "gemini-2.0-flash",
        api_key: "k",
        extra_headers: [{"x-goog-user-project", "my-project"}]
      }

      assert model.extra_headers == [{"x-goog-user-project", "my-project"}]
    end

    test "accepts custom receive_timeout" do
      model = %Gemini{model_name: "gemini-2.0-flash", api_key: "k", receive_timeout: 60_000}
      assert model.receive_timeout == 60_000
    end
  end

  describe "build_headers/1" do
    test "includes content-type with default config" do
      model = %Gemini{model_name: "gemini-2.0-flash", api_key: "test-key"}
      headers = Gemini.build_headers(model)

      assert {"content-type", "application/json"} in headers
    end

    test "appends extra_headers after required headers" do
      model = %Gemini{
        model_name: "gemini-2.0-flash",
        api_key: "test-key",
        extra_headers: [{"x-goog-user-project", "my-project"}]
      }

      headers = Gemini.build_headers(model)

      assert [
               {"content-type", "application/json"},
               {"x-goog-user-project", "my-project"}
             ] == headers
    end

    test "supports multiple extra headers" do
      model = %Gemini{
        model_name: "gemini-2.0-flash",
        api_key: "test-key",
        extra_headers: [
          {"x-goog-user-project", "my-project"},
          {"x-request-id", "req-456"}
        ]
      }

      headers = Gemini.build_headers(model)
      assert length(headers) == 3
      assert {"x-goog-user-project", "my-project"} in headers
      assert {"x-request-id", "req-456"} in headers
    end

    test "empty extra_headers produces only content-type" do
      model = %Gemini{model_name: "gemini-2.0-flash", api_key: "k", extra_headers: []}
      headers = Gemini.build_headers(model)
      assert [{"content-type", "application/json"}] == headers
    end
  end
end
