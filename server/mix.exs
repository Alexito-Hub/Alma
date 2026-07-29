defmodule Alma.MixProject do
  use Mix.Project

  def project do
    [
      app: :alma,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Alma.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.14"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},

      # Mongo + auth + JWT
      {:mongodb_driver, "~> 1.4"},
      {:bcrypt_elixir, "~> 3.1"},
      {:guardian, "~> 2.3"},

      # Useful helpers
      {:cors_plug, "~> 3.0"},
      {:uuid, "~> 1.1"}
    ]
  end
end
