# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :spitegear,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :spitegear, SpitegearWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SpitegearWeb.ErrorHTML, json: SpitegearWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Spitegear.PubSub,
  live_view: [signing_salt: "a0i7pEAm"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :spitegear, Spitegear.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  spitegear: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  spitegear: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :spitegear, Spitegear.Slack.API,
  url: URI.parse("https://slack.com"),
  channel: "spitegear",
  endpoints: [
    post_message: "/api/chat.postMessage",
    list_channels: "/api/conversations.list",
    read_channel: "/api/conversations.history",
    list_users: "/api/users.list",
    open_conversation: "/api/conversations.open"
  ],
  channel_ids: [
    spitegear: "C014W8DN81X",
    spitegear_test: "C07EC4D76JW"
  ],
  dm_ids: [
    adam: "D014TFY2K6W"
  ],
  user_ids: [
    adam: "U1LBVMGUU"
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
