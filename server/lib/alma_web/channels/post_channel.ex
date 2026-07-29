defmodule AlmaWeb.PostChannel do
  use Phoenix.Channel

  alias Alma.Posts

  @impl true
  def join("post:" <> post_id, _params, socket) do
    case Posts.get(post_id) do
      nil ->
        {:error, %{reason: "not_found"}}

      post ->
        if post["couple_id"] == socket.assigns.current_user["couple_id"] do
          Phoenix.PubSub.subscribe(Alma.PubSub, "post:#{post_id}")
          {:ok, assign(socket, :post_id, post_id)}
        else
          {:error, %{reason: "forbidden"}}
        end
    end
  end

  @impl true
  def handle_info({:new_comment, comment}, socket) do
    push(socket, "new_comment", comment)
    {:noreply, socket}
  end
end
