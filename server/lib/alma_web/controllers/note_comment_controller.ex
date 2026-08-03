defmodule AlmaWeb.NoteCommentController do
  use Phoenix.Controller, formats: [:json]
  alias Alma.Comments

  def index(conn, %{"id" => note_id}) do
    user = conn.assigns.current_user
    json(conn, %{comments: Comments.list(user, "note", note_id)})
  end

  def create(conn, %{"id" => note_id, "body" => body}) do
    case Comments.add(conn.assigns.current_user, "note", note_id, body) do
      {:ok, comment} ->
        conn |> put_status(:created) |> json(%{comment: comment})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      err ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(err)})
    end
  end
end
