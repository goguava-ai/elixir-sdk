defmodule Guava.MixProject do
  use Mix.Project

  # Tracks the Python `guava-sdk` version this port mirrors (source of truth).
  # Bump in lockstep with the Python SDK; see PARITY.md and the README.
  @version "0.32.0"
  @source_url "https://github.com/goguava-ai/elixir-sdk"

  def project do
    [
      app: :guava,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Guava",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Guava.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:websockex, "~> 0.4.3"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      # test-only websocket server
      {:bandit, "~> 1.5", only: :test},
      {:websock_adapter, "~> 0.5", only: :test},
      {:plug, "~> 1.15", only: :test},
      # tooling
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Elixir SDK for the Guava voice-agent platform."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Guava Python SDK" => "https://github.com/goguava-ai/python-sdk"
      },
      maintainers: []
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "docs/architecture.md",
        "docs/getting-started.md",
        "docs/agents.md",
        "docs/calls.md",
        "docs/tasks-and-fields.md",
        "docs/handlers.md",
        "docs/channels.md",
        "docs/campaigns.md",
        "docs/messaging.md",
        "docs/client.md",
        "docs/rag-and-llm.md",
        "docs/testing.md",
        "docs/deployment.md",
        "PARITY.md"
      ],
      groups_for_extras: [
        Guides: ~r"docs/.*"
      ]
    ]
  end
end
