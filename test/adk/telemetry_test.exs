defmodule ADK.TelemetryTest do
  # Not async because OTel SDK uses global state
  use ExUnit.Case

  alias ADK.Agent.LlmAgent
  alias ADK.Model.{LlmResponse, Mock}
  alias ADK.Tool.FunctionTool
  alias ADK.Types.{Content, FunctionCall, Part}

  describe ":telemetry events" do
    test "llm call emits start and stop events" do
      ref = make_ref()
      pid = self()

      handler = fn event, measurements, metadata, {ref, pid} ->
        send(pid, {ref, event, measurements, metadata})
      end

      :telemetry.attach("llm-start", [:adk_ex, :llm, :start], handler, {ref, pid})
      :telemetry.attach("llm-stop", [:adk_ex, :llm, :stop], handler, {ref, pid})

      on_exit(fn ->
        :telemetry.detach("llm-start")
        :telemetry.detach("llm-stop")
      end)

      meta = %{model_name: "test-model", invocation_id: "inv-1", session_id: "s-1"}

      result =
        ADK.Telemetry.span_llm_call(meta, fn ->
          :llm_result
        end)

      assert result == :llm_result

      assert_receive {^ref, [:adk_ex, :llm, :start], %{system_time: _}, %{model_name: "test-model"}}
      assert_receive {^ref, [:adk_ex, :llm, :stop], %{duration: d}, %{model_name: "test-model"}}
      assert is_integer(d)
    end

    test "llm call emits exception event on error" do
      ref = make_ref()
      pid = self()

      handler = fn event, measurements, metadata, {ref, pid} ->
        send(pid, {ref, event, measurements, metadata})
      end

      :telemetry.attach("llm-exc", [:adk_ex, :llm, :exception], handler, {ref, pid})

      on_exit(fn ->
        :telemetry.detach("llm-exc")
      end)

      meta = %{model_name: "test-model"}

      assert_raise RuntimeError, fn ->
        ADK.Telemetry.span_llm_call(meta, fn ->
          raise "boom"
        end)
      end

      assert_receive {^ref, [:adk_ex, :llm, :exception], %{duration: _}, %{error: "boom"}}
    end

    test "tool call emits start and stop events" do
      ref = make_ref()
      pid = self()

      handler = fn event, measurements, metadata, {ref, pid} ->
        send(pid, {ref, event, measurements, metadata})
      end

      :telemetry.attach("tool-start", [:adk_ex, :tool, :start], handler, {ref, pid})
      :telemetry.attach("tool-stop", [:adk_ex, :tool, :stop], handler, {ref, pid})

      on_exit(fn ->
        :telemetry.detach("tool-start")
        :telemetry.detach("tool-stop")
      end)

      meta = %{tool_name: "get_weather", function_call_id: "fc-1"}

      result =
        ADK.Telemetry.span_tool_call(meta, fn ->
          :tool_result
        end)

      assert result == :tool_result

      assert_receive {^ref, [:adk_ex, :tool, :start], %{system_time: _},
                      %{tool_name: "get_weather"}}

      assert_receive {^ref, [:adk_ex, :tool, :stop], %{duration: _}, %{tool_name: "get_weather"}}
    end
  end

  describe "OpenTelemetry spans" do
    setup do
      # Route spans to the test process (config/test.exs configures otel_simple_processor)
      :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
      :ok
    end

    test "llm call creates a call_llm span" do
      meta = %{model_name: "test-model", invocation_id: "inv-1", session_id: "s-1"}

      ADK.Telemetry.span_llm_call(meta, fn ->
        :ok
      end)

      assert_receive {:span, span}, 1000
      # span is an Erlang record: {span, trace_id, span_id, tracestate,
      # parent_span_id, parent_span_is_remote, name, ...}
      assert elem(span, 6) == "call_llm"
    end

    test "tool call creates an execute_tool span" do
      :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

      meta = %{tool_name: "my_tool", function_call_id: "fc-1"}

      ADK.Telemetry.span_tool_call(meta, fn ->
        :ok
      end)

      assert_receive {:span, span}, 1000
      assert elem(span, 6) == "execute_tool my_tool"
    end

    test "merged tools creates a span" do
      :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

      ADK.Telemetry.span_merged_tools(%{event_id: "ev-1"})

      assert_receive {:span, span}, 1000
      assert elem(span, 6) == "execute_tool (merged)"
    end
  end

  describe "full flow integration" do
    test "flow emits telemetry for model and tool calls" do
      ref = make_ref()
      pid = self()

      handler = fn event, _measurements, _metadata, {ref, pid} ->
        send(pid, {ref, event})
      end

      events = [
        [:adk_ex, :llm, :start],
        [:adk_ex, :llm, :stop],
        [:adk_ex, :tool, :start],
        [:adk_ex, :tool, :stop]
      ]

      for {event, i} <- Enum.with_index(events) do
        :telemetry.attach("flow-#{i}", event, handler, {ref, pid})
      end

      on_exit(fn ->
        for i <- 0..3, do: :telemetry.detach("flow-#{i}")
      end)

      # Setup a tool-calling flow through Runner
      session_name = :"tel_session_#{:erlang.unique_integer([:positive])}"

      {:ok, _pid} =
        ADK.Session.InMemory.start_link(name: session_name, table_prefix: session_name)

      tool =
        FunctionTool.new(
          name: "greet",
          description: "Greet",
          handler: fn _ctx, args -> {:ok, %{"greeting" => "Hi #{args["name"]}!"}} end
        )

      fc_response = %LlmResponse{
        content: %Content{
          role: "model",
          parts: [
            %Part{
              function_call: %FunctionCall{name: "greet", id: "c1", args: %{"name" => "Ada"}}
            }
          ]
        },
        turn_complete: true
      }

      final_response = %LlmResponse{
        content: Content.new_from_text("model", "Hello Ada!"),
        turn_complete: true
      }

      model = Mock.new(responses: [fc_response, final_response])
      agent = %LlmAgent{name: "tel-agent", model: model, tools: [tool]}

      {:ok, runner} =
        ADK.Runner.new(
          app_name: "test-app",
          root_agent: agent,
          session_service: session_name
        )

      _events =
        runner
        |> ADK.Runner.run("user-1", "session-1", Content.new_from_text("user", "hi"))
        |> Enum.to_list()

      # We expect at least 2 LLM calls (fc_response + final_response) and 1 tool call
      assert_receive {^ref, [:adk_ex, :llm, :start]}
      assert_receive {^ref, [:adk_ex, :llm, :stop]}
      assert_receive {^ref, [:adk_ex, :tool, :start]}
      assert_receive {^ref, [:adk_ex, :tool, :stop]}
    end
  end
end
