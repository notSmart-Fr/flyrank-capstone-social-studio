import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :flyrank_capstone_social_studio, FlyrankCapstoneSocialStudio.Repo,
  username: "postgres",
  password: "postgrespassword",
  hostname: "localhost",
  database: "flyrank_capstone_social_studio_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :flyrank_capstone_social_studio, FlyrankCapstoneSocialStudioWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "4FK+9j56QtNar7V8dFXIHvD11dbZr8QIUzQtAo+D+qF3rcneJsRLLOZIVAiGDNUu",
  server: false

# In test we don't send emails
config :flyrank_capstone_social_studio, FlyrankCapstoneSocialStudio.Mailer,
  adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# oban test configuration
config :flyrank_capstone_social_studio, Oban, testing: :manual
# Ensure Gemini API Key is empty during tests so execution routes to local fallbacks
System.put_env("GEMINI_API_KEY", "")

# Configure default AI provider adapter for test environment
config :flyrank_capstone_social_studio,
  ai_adapter: FlyrankCapstoneSocialStudio.Ai.Adapters.GeminiAdapter

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000, cleanup_interval_ms: 60_000]}
