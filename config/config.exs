# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :andnative_ai,
  ecto_repos: [AndnativeAi.Repo],
  generators: [timestamp_type: :utc_datetime]

config :andnative_ai, AndnativeAi.Repo, types: AndnativeAi.PostgrexTypes

config :andnative_ai, Oban,
  engine: Oban.Engines.Basic,
  repo: AndnativeAi.Repo,
  queues: [actions: 5],
  plugins: [
    # Monday 08:00 UTC: weekly governed-memory digest per tenant.
    {Oban.Plugins.Cron, crontab: [{"0 8 * * 1", AndnativeAi.Actions.DigestScheduler}]}
  ]

# Configures the endpoint
config :andnative_ai, AndnativeAiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AndnativeAiWeb.ErrorHTML, json: AndnativeAiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AndnativeAi.PubSub,
  live_view: [signing_salt: "oZ6wAPvV"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  andnative_ai: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  andnative_ai: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Swoosh mailer. Default to the Local adapter (in-memory preview); test and
# prod override below. No HTTP API client is needed for the Local/Test/SMTP
# adapters.
config :andnative_ai, AndnativeAi.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, false

# Default "from" identity for transactional email (prod overrides via env).
config :andnative_ai, :mailer_from, {"andnative.ai", "no-reply@andnativeai.marcelfahle.net"}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
