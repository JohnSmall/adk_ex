defmodule ADK.Model.Registry do
  @moduledoc """
  Resolves model name strings to provider structs.

  Pattern matches model name prefixes to determine the provider:
  - `"gemini-*"` → `ADK.Model.Gemini`
  - `"claude-*"` → `ADK.Model.Claude`
  """

  alias ADK.Model.{Claude, Gemini}

  @doc """
  Resolves a model name to a configured provider struct.

  Options:
  - `:api_key` — API key for the provider (required)
  - `:base_url` — override the default base URL (optional)
  """
  @spec resolve(String.t(), keyword()) :: {:ok, struct()} | {:error, :unknown_model}
  def resolve(name, opts \\ []) when is_binary(name) do
    api_key = Keyword.get(opts, :api_key)
    base_url = Keyword.get(opts, :base_url)

    cond do
      String.starts_with?(name, "gemini") ->
        model = %Gemini{model_name: name, api_key: api_key}
        model = if base_url, do: %{model | base_url: base_url}, else: model
        {:ok, model}

      String.starts_with?(name, "claude") ->
        model = %Claude{model_name: name, api_key: api_key}
        model = if base_url, do: %{model | base_url: base_url}, else: model
        {:ok, model}

      true ->
        {:error, :unknown_model}
    end
  end
end
