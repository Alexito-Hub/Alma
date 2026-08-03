defmodule AlmaWeb.CommentController do
  @moduledoc """
  Feed-post comments. The Feed has no screen in the app any more, but the
  route stays so the couple's existing threads remain readable — and so it
  carries the same couple check as every other route, which it did not.
  """
  use Phoenix.Controller, formats: [:json]
  alias Alma.{Comments, Posts}

  def create(conn, %{"id" => post_id} = params) do
    user = conn.assigns.current_user
    text = (params["body"] || params["text"] || "") |> to_string() |> String.trim()

    cond do
      text == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "empty"})

      not Comments.visible?(user, "post", post_id) ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      true ->
        case Posts.add_comment(post_id, user, text) do
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
    if Comments.visible?(conn.assigns.current_user, "post", post_id) do
      json(conn, %{comments: Posts.list_comments(post_id)})
    else
      conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end
end
