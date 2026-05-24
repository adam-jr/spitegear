import Config

config :spitegear, Spitegear.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "spitegear_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :spitegear, SpitegearWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "I/dpmc6jVhtW8Hh3TIjBjAjw4L7SD81V7uBbtnAo+p6mj4X7Sxznp1HuHdQIsbxt",
  server: false

# In test we don't send emails.
config :spitegear, Spitegear.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :spitegear, :admin_username, "admin"
config :spitegear, :admin_password, "admin"
