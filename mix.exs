defmodule ADK.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/JohnSmall/adk_ex"

  def project do
    [
      app: :adk_ex,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit, :opentelemetry_api]],
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ADK.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:elixir_uuid, "~> 1.2"},
      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry, "~> 1.5"},
      {:telemetry, "~> 1.3"}
    ]
  end

  defp description do
    "Elixir port of Google's Agent Development Kit (ADK) — agent orchestration, " <>
      "sessions, tools, LLM abstraction, plugins, and telemetry. Transport-agnostic."
  end

  defp package do
    [
      name: "adk_ex",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md
           usage-rules.md usage-rules)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        {"docs/architecture.md", title: "Architecture"},
        {"docs/onboarding.md", title: "Onboarding Guide"},
        {"usage-rules.md", title: "LLM Usage Rules"}
      ],
      groups_for_modules: [
        Core: [
          ADK.Types,
          ADK.Event,
          ADK.Event.Actions,
          ADK.Session,
          ADK.Session.State,
          ADK.Session.Service,
          ADK.Session.InMemory,
          ADK.RunConfig,
          ADK.Runner
        ],
        Agents: [
          ADK.Agent,
          ADK.Agent.InvocationContext,
          ADK.Agent.CallbackContext,
          ADK.Agent.Config,
          ADK.Agent.CustomAgent,
          ADK.Agent.LlmAgent,
          ADK.Agent.LoopAgent,
          ADK.Agent.SequentialAgent,
          ADK.Agent.ParallelAgent,
          ADK.Agent.Tree
        ],
        Tools: [
          ADK.Tool,
          ADK.Tool.Context,
          ADK.Tool.FunctionTool,
          ADK.Tool.TransferToAgent,
          ADK.Tool.LoadMemory,
          ADK.Tool.LoadArtifacts,
          ADK.Tool.Toolset
        ],
        Model: [
          ADK.Model,
          ADK.Model.LlmRequest,
          ADK.Model.LlmResponse,
          ADK.Model.Mock,
          ADK.Model.Gemini,
          ADK.Model.Claude,
          ADK.Model.Registry
        ],
        Flow: [
          ADK.Flow,
          ADK.Flow.Processors.Basic,
          ADK.Flow.Processors.ToolProcessor,
          ADK.Flow.Processors.Instructions,
          ADK.Flow.Processors.AgentTransfer,
          ADK.Flow.Processors.Contents
        ],
        Services: [
          ADK.Memory.Entry,
          ADK.Memory.Service,
          ADK.Memory.InMemory,
          ADK.Artifact.Service,
          ADK.Artifact.InMemory,
          ADK.Telemetry
        ],
        Plugins: [
          ADK.Plugin,
          ADK.Plugin.Manager
        ]
      ]
    ]
  end
end
