defmodule ADK.MixProject do
  use Mix.Project

  def project do
    [
      app: :adk,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]]
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
