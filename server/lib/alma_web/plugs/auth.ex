defmodule AlmaWeb.Plugs.Auth do
  @moduledoc "Verifies JWT in Authorization: Bearer header, assigns :current_user."

  import Plug.Conn
  alias Alma.Guardian

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user, _claims} <- Guardian.resource_from_token(token) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end
end
