defmodule AlmaWeb.Plugs.MediaAuth do
  @moduledoc """
  Gate in front of the photo, video and voice files under `/media`.

  `Plug.Static` served them to anyone who asked. The filenames are random
  UUIDs, so nothing was crawlable — but "unguessable" is not "private" for a
  couple's photo library: a URL that leaks once stays live forever, and it is
  the only part of Alma that was ever readable without a session.

  Accepts the same `Authorization: Bearer` header as the rest of the API, and
  also a `?token=` query parameter, since some media loaders can't attach a
  header to every range request they make.

  **Rollback:** `ALMA_MEDIA_PUBLIC=true` restores the old open behaviour with
  a container restart and no app rebuild. That matters during a rollout — an
  app build older than this change sends no credentials for media, so it must
  reach both phones before the gate closes.
  """

  import Plug.Conn

  alias Alma.Guardian

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["media" | _rest]} = conn, _opts) do
    if public?() or authenticated?(conn) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
      |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp public?, do: System.get_env("ALMA_MEDIA_PUBLIC") == "true"

  defp authenticated?(conn) do
    case token(conn) do
      nil -> false
      t -> match?({:ok, _user, _claims}, Guardian.resource_from_token(t))
    end
  end

  defp token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> t] ->
        t

      _ ->
        # Static files are served before the router, so query params haven't
        # been fetched yet.
        conn = fetch_query_params(conn)

        case conn.query_params["token"] do
          t when is_binary(t) and t != "" -> t
          _ -> nil
        end
    end
  end
end
