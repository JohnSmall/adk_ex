defmodule ADK.Model.ClaudeTest do
  use ExUnit.Case, async: true

  alias ADK.Model.Claude

  describe "struct defaults" do
    test "defaults extra_headers to empty list" do
      model = %Claude{model_name: "claude-sonnet-4-5", api_key: "k"}
      assert model.extra_headers == []
    end

    test "defaults receive_timeout to 120_000" do
      model = %Claude{model_name: "claude-sonnet-4-5", api_key: "k"}
      assert model.receive_timeout == 120_000
    end

    test "accepts custom extra_headers" do
      model = %Claude{
        model_name: "claude-sonnet-4-5",
        api_key: "k",
        extra_headers: [{"anthropic-beta", "prompt-caching-2024-07-31"}]
      }

      assert model.extra_headers == [{"anthropic-beta", "prompt-caching-2024-07-31"}]
    end

    test "accepts custom receive_timeout" do
      model = %Claude{model_name: "claude-sonnet-4-5", api_key: "k", receive_timeout: 300_000}
      assert model.receive_timeout == 300_000
    end
  end

  describe "build_headers/1" do
    test "includes required headers with default config" do
      model = %Claude{model_name: "claude-sonnet-4-5", api_key: "test-key"}
      headers = Claude.build_headers(model)

      assert {"x-api-key", "test-key"} in headers
      assert {"anthropic-version", "2023-06-01"} in headers
      assert {"content-type", "application/json"} in headers
    end

    test "appends extra_headers after required headers" do
      model = %Claude{
        model_name: "claude-sonnet-4-5",
        api_key: "test-key",
        extra_headers: [{"anthropic-beta", "prompt-caching-2024-07-31"}]
      }

      headers = Claude.build_headers(model)

      assert {"anthropic-beta", "prompt-caching-2024-07-31"} in headers
      # Required headers still present
      assert {"x-api-key", "test-key"} in headers
      assert {"anthropic-version", "2023-06-01"} in headers
      assert {"content-type", "application/json"} in headers
    end

    test "required headers appear before extra_headers" do
      model = %Claude{
        model_name: "claude-sonnet-4-5",
        api_key: "test-key",
        extra_headers: [{"x-custom", "val"}]
      }

      headers = Claude.build_headers(model)

      # Required headers are the first 3, custom comes after
      assert [
               {"x-api-key", "test-key"},
               {"anthropic-version", "2023-06-01"},
               {"content-type", "application/json"},
               {"x-custom", "val"}
             ] == headers
    end

    test "supports multiple extra headers" do
      model = %Claude{
        model_name: "claude-sonnet-4-5",
        api_key: "test-key",
        extra_headers: [
          {"anthropic-beta", "prompt-caching-2024-07-31"},
          {"x-request-id", "req-123"}
        ]
      }

      headers = Claude.build_headers(model)
      assert length(headers) == 5
      assert {"anthropic-beta", "prompt-caching-2024-07-31"} in headers
      assert {"x-request-id", "req-123"} in headers
    end

    test "empty extra_headers produces only required headers" do
      model = %Claude{model_name: "claude-sonnet-4-5", api_key: "k", extra_headers: []}
      headers = Claude.build_headers(model)
      assert length(headers) == 3
    end
  end
end
