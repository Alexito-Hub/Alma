defmodule AlmaWeb.NoteController do
  use Phoenix.Controller, formats: [:json]
  alias Alma.Notes

  def create(conn, %{"body" => _body} = params) do
    case Notes.create(conn.assigns.current_user, params) do
      {:ok, note} -> json(conn, %{note: note})
      err -> conn |> put_status(:bad_request) |> json(%{error: inspect(err)})
    end
  end

  def index(conn, _params) do
    cid = conn.assigns.current_user["couple_id"]
    json(conn, %{notes: Notes.list_for_couple(cid)})
  end
end
