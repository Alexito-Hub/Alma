import Config

# Runtime config (read at boot in prod).
if config_env() == :prod do
  secret_key_base =
    System.get_env("ALMA_SECRET_KEY_BASE") ||
      raise "ALMA_SECRET_KEY_BASE is not set (run `mix phx.gen.secret`)"

  host = System.get_env("ALMA_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :alma, AlmaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end

# Mongo connection is configured at runtime in every env so both dev
# and prod can point at Atlas without re-compiling.
config :alma, :mongo,
  url:
    System.get_env("ALMA_MONGO_URL") ||
      "mongodb://localhost:27017/alma",
  pool_size: String.to_integer(System.get_env("ALMA_MONGO_POOL") || "5")
