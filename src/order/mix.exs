defmodule TlaPlayground.MixProject do
  use Mix.Project

  def project do
    [
      app: :tla_playground,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {TlaPlayground.Application, []}
    ]
  end

  defp deps do
    [
      {:propcheck, "~> 1.5", only: [:dev, :test]}
    ]
  end
end
