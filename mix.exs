defmodule Hanguko.MixProject do
  use Mix.Project

  def project do
    [
      app: :hanguko,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      name: "Hanguko",
      source_url: "https://github.com/dylangleason/hanguko",
      docs: docs(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Hanguko.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Documentation built by `mix docs`. The guides are the prose; the module
  # docs fill in the detail.
  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "guides/architecture.md": [title: "Architecture"],
        "guides/domain-model.md": [title: "Domain model"]
      ],
      groups_for_extras: [Guides: ~r"guides/"],
      groups_for_modules: [
        Curriculum: [
          Hanguko.Content,
          Hanguko.Content.Deck,
          Hanguko.Content.GrammarPoint,
          Hanguko.Content.GrammarProgress,
          Hanguko.Content.Importer,
          Hanguko.Content.Item
        ],
        "Spaced repetition": [
          Hanguko.SRS,
          Hanguko.SRS.Card,
          Hanguko.SRS.Day,
          Hanguko.SRS.DeckEnrollment,
          Hanguko.SRS.Queue,
          Hanguko.SRS.ReviewLog,
          Hanguko.SRS.Scheduler,
          Hanguko.SRS.Settings
        ],
        Korean: [Hanguko.Korean],
        Accounts: [
          Hanguko.Accounts,
          Hanguko.Accounts.Scope,
          Hanguko.Accounts.User,
          Hanguko.Accounts.UserNotifier,
          Hanguko.Accounts.UserToken
        ],
        Web: [~r"HangukoWeb\."]
      ],
      nest_modules_by_prefix: [Hanguko.Content, Hanguko.SRS, HangukoWeb]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.8.13"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:yaml_elixir, "~> 2.12"},
      {:mdex, "~> 0.9"},
      {:fsrs_ex, "~> 0.1.2"},
      {:tz, "~> 0.28.2"},
      {:stream_data, "~> 1.4", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind hanguko", "esbuild hanguko"],
      "assets.deploy": [
        "tailwind hanguko --minify",
        "esbuild hanguko --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
