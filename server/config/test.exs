import Config

config :alma, AlmaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_64_chars_at_least_for_running_tests_only_okay_thx",
  server: false

config :logger, level: :warning
