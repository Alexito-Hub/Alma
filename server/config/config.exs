import Config

config :alma,
  generators: [timestamp_type: :utc_datetime],
  media_root: System.get_env("ALMA_MEDIA_ROOT") || "priv/static/media",
  media_public_prefix: "/media",
  # Surfaced by the health endpoint; works in releases too (no Mix at runtime).
  env: config_env()

config :alma, AlmaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AlmaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Alma.PubSub,
  live_view: [signing_salt: "alma_lv_salt"]

config :alma, Alma.Guardian,
  issuer: "alma",
  secret_key:
    System.get_env("ALMA_JWT_SECRET") ||
      "dev-secret-change-me-and-make-it-very-long-please-ok-thanks"

config :phoenix, :json_library, Jason
config :logger, level: :info

import_config "#{config_env()}.exs"
