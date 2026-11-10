defmodule SmsGora.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/TekservixHQ/smsgora-elixir"

  def project do
    [
      app: :smsgora,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "SmsGora",
      description:
        "Elixir client for the SMS Gora SMS Gateway API: send and receive SMS through your own Android phones, with delivery reports and webhooks.",
      source_url: @source_url,
      homepage_url: "https://tekservix.com/smsgora/",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:plug, "~> 1.14", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Website" => "https://tekservix.com/smsgora/",
        "API reference" => "https://tekservix.com/smsgora/docs/"
      },
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md", "CHANGELOG.md"], source_ref: "v#{@version}"]
  end
end
