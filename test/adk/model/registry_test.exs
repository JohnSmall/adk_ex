defmodule ADK.Model.RegistryTest do
  use ExUnit.Case, async: true

  alias ADK.Model.{Claude, Gemini, LiteLlm, Registry}

  describe "resolve/2 — Gemini" do
    test "resolves gemini-* names to Gemini struct" do
      assert {:ok, %Gemini{model_name: "gemini-2.0-flash", api_key: "k"}} =
               Registry.resolve("gemini-2.0-flash", api_key: "k")
    end

    test "accepts base_url override for Gemini" do
      assert {:ok, %Gemini{base_url: "http://proxy"}} =
               Registry.resolve("gemini-2.0-flash", api_key: "k", base_url: "http://proxy")
    end
  end

  describe "resolve/2 — Claude" do
    test "resolves claude-* names to Claude struct" do
      assert {:ok, %Claude{model_name: "claude-sonnet-4-5", api_key: "k"}} =
               Registry.resolve("claude-sonnet-4-5", api_key: "k")
    end
  end

  describe "resolve/2 — DeepSeek (via Claude Anthropic-compatible endpoint)" do
    test "resolves deepseek-* names to Claude with DeepSeek base_url" do
      assert {:ok,
              %Claude{
                model_name: "deepseek-v4-pro",
                api_key: "k",
                base_url: "https://api.deepseek.com/anthropic/v1"
              }} = Registry.resolve("deepseek-v4-pro", api_key: "k")
    end

    test "resolves deepseek-v4-flash" do
      assert {:ok, %Claude{model_name: "deepseek-v4-flash"}} =
               Registry.resolve("deepseek-v4-flash", api_key: "k")
    end

    test "lets the caller override the DeepSeek base_url" do
      assert {:ok, %Claude{base_url: "http://proxy"}} =
               Registry.resolve("deepseek-v4-pro", api_key: "k", base_url: "http://proxy")
    end
  end

  describe "resolve/2 — OpenAI (via LiteLlm)" do
    test "resolves gpt-* names to LiteLlm with OpenAI base_url" do
      assert {:ok,
              %LiteLlm{
                model_name: "gpt-4o",
                api_key: "k",
                base_url: "https://api.openai.com/v1"
              }} = Registry.resolve("gpt-4o", api_key: "k")
    end

    test "resolves o1 reasoning models to LiteLlm with OpenAI base_url" do
      assert {:ok, %LiteLlm{model_name: "o1-mini", base_url: "https://api.openai.com/v1"}} =
               Registry.resolve("o1-mini", api_key: "k")
    end

    test "resolves o3 reasoning models to LiteLlm with OpenAI base_url" do
      assert {:ok, %LiteLlm{model_name: "o3-mini", base_url: "https://api.openai.com/v1"}} =
               Registry.resolve("o3-mini", api_key: "k")
    end

    test "lets the caller override the OpenAI base_url" do
      assert {:ok, %LiteLlm{base_url: "https://azure.example.com"}} =
               Registry.resolve("gpt-4o",
                 api_key: "k",
                 base_url: "https://azure.example.com"
               )
    end
  end

  describe "resolve/2 — slash-namespaced (LiteLLM proxy)" do
    test "resolves provider/model names to LiteLlm when base_url is provided" do
      assert {:ok,
              %LiteLlm{
                model_name: "openai/gpt-4o",
                api_key: "sk-proxy",
                base_url: "http://localhost:4000"
              }} =
               Registry.resolve("openai/gpt-4o",
                 api_key: "sk-proxy",
                 base_url: "http://localhost:4000"
               )
    end

    test "resolves anthropic/* proxy names" do
      assert {:ok, %LiteLlm{model_name: "anthropic/claude-3-5-sonnet-20241022"}} =
               Registry.resolve("anthropic/claude-3-5-sonnet-20241022",
                 api_key: "sk",
                 base_url: "http://localhost:4000"
               )
    end

    test "returns error when slash-namespaced name has no base_url" do
      assert {:error, :base_url_required} =
               Registry.resolve("openai/gpt-4o", api_key: "sk")
    end
  end

  describe "resolve/2 — unknown" do
    test "returns :unknown_model for names that don't match any pattern" do
      assert {:error, :unknown_model} = Registry.resolve("llama-3", api_key: "k")
      assert {:error, :unknown_model} = Registry.resolve("random-name", api_key: "k")
    end
  end

  describe "resolve/2 — extra_headers and receive_timeout passthrough" do
    test "forwards extra_headers to Gemini" do
      assert {:ok, %Gemini{extra_headers: [{"x-custom", "v"}]}} =
               Registry.resolve("gemini-2.0-flash", api_key: "k", extra_headers: [{"x-custom", "v"}])
    end

    test "forwards receive_timeout to Gemini" do
      assert {:ok, %Gemini{receive_timeout: 60_000}} =
               Registry.resolve("gemini-2.0-flash", api_key: "k", receive_timeout: 60_000)
    end

    test "forwards extra_headers to Claude" do
      assert {:ok, %Claude{extra_headers: [{"anthropic-beta", "caching"}]}} =
               Registry.resolve("claude-sonnet-4-5", api_key: "k", extra_headers: [{"anthropic-beta", "caching"}])
    end

    test "forwards receive_timeout to Claude" do
      assert {:ok, %Claude{receive_timeout: 300_000}} =
               Registry.resolve("claude-sonnet-4-5", api_key: "k", receive_timeout: 300_000)
    end

    test "forwards extra_headers to DeepSeek (Claude struct)" do
      assert {:ok, %Claude{extra_headers: [{"x-ds", "v"}], base_url: "https://api.deepseek.com/anthropic/v1"}} =
               Registry.resolve("deepseek-v4-pro", api_key: "k", extra_headers: [{"x-ds", "v"}])
    end

    test "forwards receive_timeout to DeepSeek (Claude struct)" do
      assert {:ok, %Claude{receive_timeout: 90_000}} =
               Registry.resolve("deepseek-v4-pro", api_key: "k", receive_timeout: 90_000)
    end

    test "forwards extra_headers to OpenAI (LiteLlm)" do
      assert {:ok, %LiteLlm{extra_headers: [{"x-org", "org-1"}]}} =
               Registry.resolve("gpt-4o", api_key: "k", extra_headers: [{"x-org", "org-1"}])
    end

    test "forwards receive_timeout to OpenAI (LiteLlm)" do
      assert {:ok, %LiteLlm{receive_timeout: 45_000}} =
               Registry.resolve("gpt-4o", api_key: "k", receive_timeout: 45_000)
    end

    test "forwards extra_headers to slash-namespaced (LiteLlm)" do
      assert {:ok, %LiteLlm{extra_headers: [{"x-proxy", "v"}]}} =
               Registry.resolve("openai/gpt-4o", api_key: "k", base_url: "http://proxy", extra_headers: [{"x-proxy", "v"}])
    end

    test "forwards receive_timeout to slash-namespaced (LiteLlm)" do
      assert {:ok, %LiteLlm{receive_timeout: 200_000}} =
               Registry.resolve("openai/gpt-4o", api_key: "k", base_url: "http://proxy", receive_timeout: 200_000)
    end

    test "defaults are preserved when transport opts are not passed" do
      assert {:ok, %Claude{extra_headers: [], receive_timeout: 120_000}} =
               Registry.resolve("claude-sonnet-4-5", api_key: "k")

      assert {:ok, %Gemini{extra_headers: [], receive_timeout: 120_000}} =
               Registry.resolve("gemini-2.0-flash", api_key: "k")

      assert {:ok, %LiteLlm{extra_headers: [], receive_timeout: 120_000}} =
               Registry.resolve("gpt-4o", api_key: "k")
    end
  end
end
