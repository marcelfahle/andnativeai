import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :andnative_ai, AndnativeAi.Repo,
  username: System.get_env("DATABASE_USER", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres"),
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  database: "andnative_ai_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :andnative_ai, AndnativeAiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ngBQWR4SSn3xm2rl4Pt2EfUPCCBmscZ4W4ytxFh0kigRz91qP+bQ7F3Jf0JL+12m",
  server: false

# Only use the lowest bcrypt cost factor in tests so the suite stays fast.
config :bcrypt_elixir, :log_rounds, 1

# Capture emails in memory so tests can assert on them.
config :andnative_ai, Oban, testing: :manual

config :andnative_ai, :embeddings_provider, AndnativeAi.Memory.Embeddings.Deterministic

config :andnative_ai, AndnativeAi.Mailer, adapter: Swoosh.Adapters.Test

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Fixed test-only encryption key for secrets at rest; prod requires CLOAK_KEY.
config :andnative_ai, AndnativeAi.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("2vAT/GJmXB2SexbBBpvVYJ2H1v5vqs0hZpIG4HXt9fs=")}
  ]
