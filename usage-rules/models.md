# ADK Ex — Model Providers

`adk_ex` ships four model providers. All implement the `ADK.Model` behaviour (`name/1`, `generate_content/3`).

| Provider | Module | Endpoint | When to use |
|---|---|---|---|
| Gemini | `ADK.Model.Gemini` | Google Generative Language REST API | Google-native Gemini models |
| Claude | `ADK.Model.Claude` | Anthropic Messages API | Claude direct (no proxy) |
| LiteLlm | `ADK.Model.LiteLlm` | OpenAI Chat Completions wire format | OpenAI, LiteLLM proxy, or any OpenAI-compatible endpoint |
| Mock | `ADK.Model.Mock` | In-process Agent | Tests |

## Rule: use `ADK.Model.LiteLlm` for OpenAI

This mirrors Python ADK's `LiteLlm(model="openai/gpt-4o")`. Do **not** write a bespoke OpenAI client — the Chat Completions format is a universal contract that already covers what we need, and the LiteLLM proxy extends it to 100+ providers.

```elixir
%ADK.Model.LiteLlm{
  model_name: "gpt-4o",
  api_key: System.fetch_env!("OPENAI_API_KEY"),
  base_url: "https://api.openai.com/v1"  # default
}
```

Shortcut via the registry:

```elixir
{:ok, model} = ADK.Model.Registry.resolve("gpt-4o", api_key: key)
```

## Rule: use a LiteLLM proxy for multi-provider routing

When you want to switch providers at runtime, rate-limit globally, log centrally, or use a provider not directly supported, run the [LiteLLM proxy](https://docs.litellm.ai/) and point `base_url` at it. Model names use `provider/model` syntax.

```elixir
%ADK.Model.LiteLlm{
  model_name: "anthropic/claude-3-5-sonnet-20241022",
  api_key: "sk-litellm-master-key",
  base_url: "http://localhost:4000"
}
```

Works with `anthropic/*`, `openai/*`, `ollama/*`, `groq/*`, `together_ai/*`, `openrouter/*`, `bedrock/*`, `vertex_ai/*`, etc. Registry resolves any name containing `/` to LiteLlm (requires `:base_url`).

## Rule: use `ADK.Model.LiteLlm` for any OpenAI-compatible endpoint

Groq, Together, OpenRouter, Ollama (OpenAI compatibility mode), vLLM, LM Studio, Azure OpenAI, and local inference servers all expose `/chat/completions`. Just set `base_url`.

```elixir
# Ollama
%ADK.Model.LiteLlm{
  model_name: "llama3",
  api_key: "none",
  base_url: "http://localhost:11434/v1"
}

# Groq
%ADK.Model.LiteLlm{
  model_name: "llama-3.3-70b-versatile",
  api_key: System.fetch_env!("GROQ_API_KEY"),
  base_url: "https://api.groq.com/openai/v1"
}
```

## Rule: use Claude/Gemini providers for direct access

If you don't need multi-provider routing and you're using Anthropic or Google directly, the dedicated providers are simpler (no translation layer, no proxy process, native auth).

## Rule: use DeepSeek via the Anthropic-compatible endpoint

DeepSeek exposes an Anthropic-compatible API at `https://api.deepseek.com/anthropic/v1`. The registry resolves `deepseek-*` model names to a `Claude` struct pointed at that endpoint.

```elixir
{:ok, model} = ADK.Model.Registry.resolve("deepseek-v4-pro", api_key: key)

# Or construct directly:
%ADK.Model.Claude{
  model_name: "deepseek-v4-pro",
  api_key: System.fetch_env!("DEEPSEEK_API_KEY"),
  base_url: "https://api.deepseek.com/anthropic/v1"
}
```

## Registry resolution summary

```elixir
ADK.Model.Registry.resolve(name, opts)
```

| Pattern | Resolves to | `:base_url` |
|---|---|---|
| `"gemini-*"` | `Gemini` | optional override |
| `"claude-*"` | `Claude` | optional override |
| `"deepseek-*"` | `Claude` (DeepSeek endpoint) | optional override |
| `"gpt-*"`, `"o1*"`, `"o3*"` | `LiteLlm` (OpenAI) | optional override |
| `"provider/model"` (contains `/`) | `LiteLlm` | **required** |
| anything else | `{:error, :unknown_model}` | — |

All patterns require `:api_key` in `opts`.

## Function calling

Tools defined via `ADK.Tool.FunctionTool.new(handler: ...)` are serialized by every provider. No provider-specific tool syntax is needed. `LiteLlm` maps to/from OpenAI's `tool_calls` format; `Claude` maps to `tool_use`/`tool_result`; `Gemini` maps to `functionCall`/`functionResponse`. Your code stays the same.

## Testing rule: use `ADK.Model.Mock.new/1`

For unit tests, inject a Mock model rather than hitting any real API. Integration tests that exercise real providers live under `test/integration/` and are tagged `:integration` (excluded by default — run with `mix test --include integration`).

```elixir
model = ADK.Model.Mock.new(responses: [response1, response2])
```

Never construct `%ADK.Model.Mock{}` directly — `new/1` starts the Agent process that sequences responses.
