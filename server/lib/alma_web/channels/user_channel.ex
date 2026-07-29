defmodule AlmaWeb.UserChannel do
  @moduledoc """
  Per-user notifications: incoming couple requests, accepted/rejected
  responses, and any other event that targets a single user before they're
  part of a couple.
  """
  use Phoenix.Channel

  @impl true
  def join("user:" <> user_id, _params, socket) do
    if socket.assigns.current_user["_id"] == user_id do
      Phoenix.PubSub.subscribe(Alma.PubSub, "user:#{user_id}")
      {:ok, socket}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  @impl true
  def handle_info({event, payload}, socket) when is_atom(event) do
    push(socket, Atom.to_string(event), payload)
    {:noreply, socket}
  end
end
