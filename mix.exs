defmodule AtomVMTang25KHLS.MixProject do
  use Mix.Project

  def project do
    [
      app: :atomvm_tang25k_hls,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib"],
      deps: deps()
    ]
  end

  def application, do: []

  defp deps do
    [
      {:elixir_hls, git: "https://github.com/elixir-hls/elixir-hls.git"},
      {:atomvm_tang25k, git: "https://github.com/elixir-hls/atomvm-tang25k.git", app: false, compile: false}
    ]
  end
end
