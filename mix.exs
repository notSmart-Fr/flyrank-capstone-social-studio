defmodule FlyrankCapstoneSocialStudio.MixProject do
  use Mix.Project

  def project do
    [
      app: :flyrank_capstone_social_studio,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      # -----------------------------------------------------------------------
      # ExDoc Documentation Configuration
      # -----------------------------------------------------------------------
      name: "Flyrank Capstone Social Studio",
      source_url: "https://github.com/notSmart-Fr/flyrank-capstone-social-studio",
      docs: [
        main: "content_ingestion_and_grounding",
        extras: [
          "guides/content_ingestion_and_grounding.md",
          "guides/publishing_and_dispatch.md"
        ],
        groups_for_extras: [
          "Architecture & Guides": [
            "guides/content_ingestion_and_grounding.md",
            "guides/publishing_and_dispatch.md"
          ]
        ],
        groups_for_modules: [
          "Content Pipeline": [
            FlyrankCapstoneSocialStudio.Content,
            FlyrankCapstoneSocialStudio.Content.Post,
            FlyrankCapstoneSocialStudio.Content.Variant,
            FlyrankCapstoneSocialStudio.Content.IdempotencyKey
          ],
          "AI Generation & Auditing": [
            FlyrankCapstoneSocialStudio.Content.GenerateAiVariants.Core,
            FlyrankCapstoneSocialStudio.Content.GroundingVerifier,
            FlyrankCapstoneSocialStudio.Content.AiGenerator,
            FlyrankCapstoneSocialStudio.Ai.Adapters.GeminiAdapter,
            FlyrankCapstoneSocialStudio.Ai.Provider
          ],
          "Background Workers": [
            FlyrankCapstoneSocialStudio.Content.GenerateAiVariants.Worker
          ]
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {FlyrankCapstoneSocialStudio.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
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
      {:phoenix, "~> 1.8.13"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:ecto_psql_extras, "~> 0.8.8"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:oban, "~> 2.18"},
      {:floki, "~> 0.38.4"},
      {:petal_components, "~> 4.0"},
      {:hammer, "~> 6.1"},
      # Local HTTP server mock for testing real HTTP calls (timeouts, 404s, 500s)
      {:bypass, "~> 2.1", only: :test},

      # Property-based testing (generates randomized inputs for edge cases)
      {:stream_data, "~> 1.0", only: :test},

      # Factory data generation (clean test structs without manual boilerplate)
      {:ex_machina, "~> 2.8", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false, warn_if_outdated: true}
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
      "assets.build": [
        "compile",
        "tailwind flyrank_capstone_social_studio",
        "esbuild flyrank_capstone_social_studio"
      ],
      "assets.deploy": [
        "tailwind flyrank_capstone_social_studio --minify",
        "esbuild flyrank_capstone_social_studio --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
