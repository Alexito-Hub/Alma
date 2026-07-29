defmodule AlmaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :alma

  @session_options [
    store: :cookie,
    key: "_alma_key",
    signing_salt: "alma_session_salt",
    same_site: "Lax"
  ]

  socket "/socket", AlmaWeb.UserSocket,
    websocket: true,
    longpoll: false

  plug Plug.Static,
    at: "/media",
    from: {:alma, "priv/static/media"},
    gzip: false

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, {:multipart, length: 1_073_741_824}, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug CORSPlug, origin: ["*"]
  plug AlmaWeb.Router
end
