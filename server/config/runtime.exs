import Config

# Runtime config (read at boot in prod).
if config_env() == :prod do
  secret_key_base =
    System.get_env("ALMA_SECRET_KEY_BASE") ||
      raise "ALMA_SECRET_KEY_BASE is not set (run `mix phx.gen.secret`)"

  host = System.get_env("ALMA_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # Signs every session token. The dev fallback in config.exs is a literal in
  # a public repo, so production has to bring its own or refuse to start —
  # anyone holding that literal could mint a token for either account.
  jwt_secret =
    System.get_env("ALMA_JWT_SECRET") ||
      raise "ALMA_JWT_SECRET is not set (run `mix phx.gen.secret`)"

  # Origin check for the WebSocket, which used to be off entirely. The Flutter
  # client sends no Origin header (Phoenix lets those through), so this only
  # constrains browsers; ALMA_CHECK_ORIGIN=false is the escape hatch if some
  # client ever turns out to send one.
  check_origin =
    case System.get_env("ALMA_CHECK_ORIGIN") do
      "false" -> false
      _ -> ["https://#{host}", "wss://#{host}"]
    end

  config :alma, AlmaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    check_origin: check_origin,
    server: true

  config :alma, Alma.Guardian, issuer: "alma", secret_key: jwt_secret
end

# Mongo connection is configured at runtime in every env so both dev
# and prod can point at Atlas without re-compiling.
config :alma, :mongo,
  url:
    System.get_env("ALMA_MONGO_URL") ||
      "mongodb://localhost:27017/alma",
  pool_size: String.to_integer(System.get_env("ALMA_MONGO_POOL") || "5")
