import Config

# Use simple processor for OTel span tests.
# Per-test setup calls :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
# to route spans to the test process.
config :opentelemetry,
  traces_exporter: :none,
  processors: [
    {:otel_simple_processor, %{}}
  ]
