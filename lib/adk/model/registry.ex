defmodule ADK.Model.Registry do
  @moduledoc """
  Resolves model name strings to provider structs.

  Pattern matches model name prefixes to determine the provider:
  - `"gemini-*"` → `ADK.Model.Gemini`
  - `"claude-*"` → `ADK.Model.Claude` (direct Anthropic API)
  - `"deepseek-*"` → `ADK.Model.Claude` configured for DeepSeek's
    Anthropic-compatible endpoint (`base_url: "https://api.deepseek.com/anthropic/v1"`)
  - `"gpt-*"`, `"o1*"`, `"o3*"` → `ADK.Model.LiteLlm` configured for OpenAI
    (`base_url: "https://api.openai.com/v1"`)
  - Any name containing `"/"` (e.g. `"openai/gpt-4o"`, `"anthropic/claude-3-5-sonnet-20241022"`,
    `"ollama/llama3"`) → `ADK.Model.LiteLlm`. These are the model strings understood
    by the [LiteLLM proxy](https://docs.litellm.ai/) and require `:base_url` to be
    passed via `opts` so we know where the proxy is running.

  To use any other OpenAI-compatible endpoint (Groq, Together, OpenRouter,
  vLLM, LM Studio, etc.) construct the `ADK.Model.LiteLlm` struct directly
  rather than going through the registry.
  """

  alias ADK.Model.{Claude, Gemini, LiteLlm}

  @openai_base_url "https://api.openai.com/v1"
  @deepseek_anthropic_base_url "https://api.deepseek.com/anthropic/v1"

  @doc """
  Resolves a model name to a configured provider struct.

  Options:
  - `:api_key` — API key for the provider (required)
  - `:base_url` — override the default base URL (optional for Gemini/Claude/OpenAI;
    **required** for slash-namespaced names like `"openai/gpt-4o"` that target a
    LiteLLM proxy)
  """
  @spec resolve(String.t(), keyword()) :: {:ok, struct()} | {:error, atom()}
  def resolve(name, opts \\ []) when is_binary(name) do
    api_key = Keyword.get(opts, :api_key)
    base_url = Keyword.get(opts, :base_url)

    cond do
      String.starts_with?(name, "gemini") ->
        model = %Gemini{model_name: name, api_key: api_key}
        {:ok, maybe_override_base_url(model, base_url)}

      String.starts_with?(name, "claude") ->
        model = %Claude{model_name: name, api_key: api_key}
        {:ok, maybe_override_base_url(model, base_url)}

      String.starts_with?(name, "deepseek") ->
        model = %Claude{
          model_name: name,
          api_key: api_key,
          base_url: base_url || @deepseek_anthropic_base_url
        }

        {:ok, model}

      String.starts_with?(name, ["gpt", "o1", "o3"]) ->
        model = %LiteLlm{
          model_name: name,
          api_key: api_key,
          base_url: base_url || @openai_base_url
        }

        {:ok, model}

      String.contains?(name, "/") ->
        resolve_namespaced(name, api_key, base_url)

      true ->
        {:error, :unknown_model}
    end
  end

  defp resolve_namespaced(_name, _api_key, nil), do: {:error, :base_url_required}

  defp resolve_namespaced(name, api_key, base_url) do
    model = %LiteLlm{model_name: name, api_key: api_key, base_url: base_url}
    {:ok, model}
  end

  defp maybe_override_base_url(model, nil), do: model
  defp maybe_override_base_url(model, base_url), do: %{model | base_url: base_url}
end
