defmodule AlmaWeb.MediaController do
  use Phoenix.Controller, formats: [:json]
  alias Alma.Media

  def upload(conn, %{"file" => %Plug.Upload{} = up}) do
    case Media.store(conn.assigns.current_user, up) do
      {:ok, media} -> json(conn, %{url: media["url"], id: media["_id"]})
      err -> conn |> put_status(:bad_request) |> json(%{error: inspect(err)})
    end
  end
end
