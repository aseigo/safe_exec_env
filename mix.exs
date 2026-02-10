defmodule SafeExecEnv.MixProject do
  use Mix.Project

  def project do
    [
      app: :safe_exec_env,
      version: "0.1.2",
      elixir: "~> 1.4",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.16", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "A safe(r) way to run native code bindings which may crash on the BEAM"
  end

  defp package() do
    [
      # These are the default files included in the package
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Aaron Seigo"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/aseigo/safe_exec_env"}
    ]
  end
end
