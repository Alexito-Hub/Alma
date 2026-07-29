defmodule AlmaWeb.PostController do
  use Phoenix.Controller, formats: [:json]
  alias Alma.Posts

  def create(conn, params) do
    case Posts.create(conn.assigns.current_user, params) do
      {:ok, post} ->
        # Broadcast so the partner's feed channel can prepend in realtime.
        if cid = conn.assigns.current_user["couple_id"] do
          Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{cid}", {:new_post, post})
        end

        conn |> put_status(:created) |> json(%{id: post["_id"], post: post})

      {:error, err} ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(err)})
    end
  end

  def index(conn, _params) do
    cid = conn.assigns.current_user["couple_id"]
    json(conn, %{posts: Posts.list_for_couple(cid)})
  end

  def show(conn, %{"id" => id}) do
    case Posts.get(id) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
      p -> json(conn, %{post: p})
    end
  end
end
