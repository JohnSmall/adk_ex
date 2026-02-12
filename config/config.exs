import Config

# Disable OTLP exporter by default — users configure their own exporter in their app.
# Without this, opentelemetry attempts to use opentelemetry_exporter which is not a dependency.
config :opentelemetry,
  traces_exporter: :none

import_config "#{config_env()}.exs"
