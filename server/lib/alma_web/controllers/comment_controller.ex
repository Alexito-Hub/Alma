defmodule AlmaWeb.CommentController do
  use Phoenix.Controller, formats: [:json]
  alias Alma.Posts

  def create(conn, %{"id" => post_id} = params) do
    text = (params["body"] || params["text"] || "") |> to_string() |> String.trim()

    cond do
      text == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "empty"})

      true ->
        case Posts.add_comment(post_id, conn.assigns.current_user, text) do
          {:ok, comment} ->
            Phoenix.PubSub.broadcast(
              Alma.PubSub,
              "post:#{post_id}",
              {:new_comment, comment}
            )

            json(conn, %{comment: comment})

          err ->
            conn |> put_status(:bad_request) |> json(%{error: inspect(err)})
        end
    end
  end

  def index(conn, %{"id" => post_id}) do
    json(conn, %{comments: Posts.list_comments(post_id)})
  end
end
