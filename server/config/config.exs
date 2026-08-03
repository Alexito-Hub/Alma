import Config

config :alma,
  generators: [timestamp_type: :utc_datetime],
  media_root: System.get_env("ALMA_MEDIA_ROOT") || "priv/static/media",
  media_public_prefix: "/media",
  # Biggest single upload the parser will buffer. It used to be a gigabyte,
  # which is three orders of magnitude past anything the app sends after
  # compression. Compile-time: `Plug.Parsers` is initialised when the endpoint
  # is built, so a runtime value would never reach it.
  max_upload_mb: 256,
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

# Development/test default only. Production takes its secret from
# ALMA_JWT_SECRET in runtime.exs and refuses to boot without one — this
# literal is in a public repo, so anything signed with it is not secret.
config :alma, Alma.Guardian,
  issuer: "alma",
  secret_key:
    System.get_env("ALMA_JWT_SECRET") ||
      "dev-only-secret-not-used-in-prod-see-runtime-exs-and-env-example"

config :phoenix, :json_library, Jason
config :logger, level: :info

import_config "#{config_env()}.exs"
