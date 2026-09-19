defmodule Edit.MixProject do
  use Mix.Project

  def project do
    [
      app: :edit_runtime,
      version: "0.1.0",
      elixir: ">= 1.20.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {EditRuntime.Application, []}]
  end

  defp deps do
    [
      {:jido, git: "https://github.com/agentjido/jido.git", tag: "v2.3.3"},
      {:jevex, git: "https://github.com/kentaro/jevex.git", depth: 1},
      {:req, git: "https://github.com/wojtekmach/req.git", tag: "v0.7.4", override: true},
      {:jason, "~> 1.4"}
    ]
  end
end
