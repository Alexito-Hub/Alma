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

  # The gate has to come first: `Plug.Static` answers and halts.
  plug AlmaWeb.Plugs.MediaAuth

  plug Plug.Static,
    at: "/media",
    from: {:alma, "priv/static/media"},
    gzip: false

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  @max_upload_bytes Application.compile_env(:alma, :max_upload_mb, 256) * 1_024 * 1_024

  plug Plug.Parsers,
    parsers: [:urlencoded, {:multipart, length: @max_upload_bytes}, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug CORSPlug, origin: &AlmaWeb.Cors.origins/0
  plug AlmaWeb.Router
end
