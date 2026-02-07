defmodule ADK.Integration.GeminiTest do
  @moduledoc """
  Integration tests for the Gemini provider.

  Run with: mix test test/integration/ --include integration
  Requires GEMINI_API_KEY environment variable.
  """
  use ExUnit.Case

  @moduletag :integration

  alias ADK.Agent.LlmAgent
  alias ADK.Model.Gemini
  alias ADK.Runner
  alias ADK.Tool.FunctionTool
  alias ADK.Types.Content

  setup do
    api_key = System.get_env("GEMINI_API_KEY")

    if is_nil(api_key) do
      IO.puts("Skipping Gemini integration test: GEMINI_API_KEY not set")
      :ok
    end

    name = :"gemini_session_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = ADK.Session.InMemory.start_link(name: name, table_prefix: name)
    {:ok, session_service: name, api_key: api_key}
  end

  @tag :integration
  test "simple question", ctx do
    if is_nil(ctx[:api_key]), do: flunk("GEMINI_API_KEY required")

    model = %Gemini{model_name: "gemini-2.0-flash", api_key: ctx[:api_key]}
    agent = %LlmAgent{name: "gemini-agent", model: model, instruction: "Be brief."}

    {:ok, runner} =
      Runner.new(
        app_name: "test",
        root_agent: agent,
        session_service: ctx[:session_service]
      )

    events =
      runner
      |> Runner.run("user-1", "s1", Content.new_from_text("user", "What is 2+2? Reply with just the number."))
      |> Enum.to_list()

    assert events != []
    final = List.last(events)
    assert final.content != nil
    text = hd(final.content.parts).text
    assert text =~ "4"
  end

  @tag :integration
  test "tool call with Gemini", ctx do
    if is_nil(ctx[:api_key]), do: flunk("GEMINI_API_KEY required")

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
          {:ok, %{"city" => city, "temperature" => "15°C", "condition" => "Partly cloudy"}}
        end
      )

    model = %Gemini{model_name: "gemini-2.0-flash", api_key: ctx[:api_key]}

    agent = %LlmAgent{
      name: "weather-gemini",
      model: model,
      tools: [weather_tool],
      instruction: "You are a weather assistant. Use the get_weather tool to answer weather questions."
    }

    {:ok, runner} =
      Runner.new(
        app_name: "test",
        root_agent: agent,
        session_service: ctx[:session_service]
      )

    events =
      runner
      |> Runner.run("user-1", "s1", Content.new_from_text("user", "What's the weather in London?"))
      |> Enum.to_list()

    assert events != []

    texts =
      events
      |> Enum.filter(fn e -> e.content != nil end)
      |> Enum.flat_map(fn e -> Enum.map(e.content.parts, & &1.text) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    # Should mention the weather data from the tool
    assert texts =~ "15" or texts =~ "cloudy" or texts =~ "London"
  end
end
