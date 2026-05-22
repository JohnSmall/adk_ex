# Run with:
#   OPENAI_API_KEY=sk-... mix run examples/openai.exs
#
# This example mirrors Google's Python ADK `LiteLlm(model="openai/gpt-4o")`
# pattern. The `ADK.Model.LiteLlm` provider speaks the OpenAI Chat Completions
# wire format, so it works against:
#   - OpenAI directly (shown here)
#   - A LiteLLM proxy fronting any of 100+ providers
#   - Any OpenAI-compatible endpoint (Groq, Together, OpenRouter, Ollama, ...)

alias ADK.Agent.LlmAgent
alias ADK.Model.LiteLlm
alias ADK.Runner
alias ADK.Tool.FunctionTool
alias ADK.Types.Content

api_key = System.fetch_env!("OPENAI_API_KEY")

# A simple tool the agent can call.
weather_tool =
  FunctionTool.new(
    name: "get_weather",
    description: "Gets the current weather for a city",
    parameters: %{
      "type" => "object",
      "properties" => %{
        "city" => %{"type" => "string", "description" => "The city name"}
      },
      "required" => ["city"]
    },
    handler: fn _ctx, args ->
      city = Map.get(args, "city", "Unknown")
      {:ok, %{"city" => city, "temperature" => "15C", "condition" => "Partly cloudy"}}
    end
  )

# Option 1 — construct the provider struct directly.
model = %LiteLlm{
  model_name: "gpt-4o",
  api_key: api_key,
  base_url: "https://api.openai.com/v1"
}

# Option 2 — go through the registry (uncomment to use):
# {:ok, model} = ADK.Model.Registry.resolve("gpt-4o", api_key: api_key)

# Option 3 — talk to a LiteLLM proxy for multi-provider routing (uncomment):
# model = %LiteLlm{
#   model_name: "openai/gpt-4o",
#   api_key: System.fetch_env!("LITELLM_PROXY_KEY"),
#   base_url: "http://localhost:4000"
# }

agent = %LlmAgent{
  name: "weather-bot",
  model: model,
  tools: [weather_tool],
  instruction: "You are a concise weather assistant. Use get_weather when asked."
}

# Start an in-memory session store.
session_name = :openai_example_session
{:ok, _pid} = ADK.Session.InMemory.start_link(name: session_name, table_prefix: session_name)

{:ok, runner} =
  Runner.new(
    app_name: "openai-example",
    root_agent: agent,
    session_service: session_name
  )

events =
  runner
  |> Runner.run("user-1", "s1", Content.new_from_text("user", "What's the weather in London?"))
  |> Enum.to_list()

# Print the agent's final answer.
final = List.last(events)

if final && final.content do
  text =
    final.content.parts
    |> Enum.map(& &1.text)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("")

  IO.puts("\n--- Agent response ---")
  IO.puts(text)
else
  IO.puts("No final content returned.")
end
