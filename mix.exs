defmodule AtomVMTang25KHLS.MixProject do
  use Mix.Project

  def project do
    [
      app: :atomvm_tang25k_hls,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib"],
      deps: deps(),
      description: "Elixir HLS's target for the Sipeed Tang Primer 25K: the SoC, AtomVM and the Mix tasks' work on it",
      package: [
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => "https://github.com/elixir-hls/atomvm-tang25k-hls"},
        files: ~w(lib gateware scripts board_gpio.json docs mix.exs README.md LICENSE),
        exclude_patterns: [~r/__pycache__/, ~r/\.pyc$/]
      ]
    ]
  end

  def application, do: []

  defp deps do
    [
      {:elixir_hls, "~> 0.1"},
      {:atomvm_tang25k, "~> 0.1"}
    ]
  end
end
