defmodule AlmaWeb.CoupleChannel do
  use Phoenix.Channel

  @impl true
  def join("couple:" <> couple_id, _params, socket) do
    user = socket.assigns.current_user

    if user["couple_id"] == couple_id do
      Phoenix.PubSub.subscribe(Alma.PubSub, "couple:#{couple_id}")
      {:ok, assign(socket, :couple_id, couple_id)}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  @impl true
  def handle_info({:status_updated, payload}, socket) do
    push(socket, "status_updated", payload)
    {:noreply, socket}
  end

  def handle_info({:new_post, post}, socket) do
    push(socket, "new_post", post)
    {:noreply, socket}
  end

  def handle_info({:settings_updated, settings}, socket) do
    push(socket, "settings_updated", settings)
    {:noreply, socket}
  end

  def handle_info({:partner_updated, payload}, socket) do
    push(socket, "partner_updated", payload)
    {:noreply, socket}
  end

  def handle_info({:new_note, note}, socket) do
    push(socket, "new_note", note)
    {:noreply, socket}
  end

  def handle_info({:new_special_date, doc}, socket) do
    push(socket, "new_special_date", doc)
    {:noreply, socket}
  end

  def handle_info({:note_updated, note}, socket) do
    push(socket, "note_updated", note)
    {:noreply, socket}
  end

  def handle_info({:note_deleted, payload}, socket) do
    push(socket, "note_deleted", payload)
    {:noreply, socket}
  end

  def handle_info({:post_updated, post}, socket) do
    push(socket, "post_updated", post)
    {:noreply, socket}
  end

  def handle_info({:post_deleted, payload}, socket) do
    push(socket, "post_deleted", payload)
    {:noreply, socket}
  end

  def handle_info({:special_date_deleted, payload}, socket) do
    push(socket, "special_date_deleted", payload)
    {:noreply, socket}
  end

  def handle_info({:new_comment, doc}, socket) do
    push(socket, "new_comment", doc)
    {:noreply, socket}
  end

  def handle_info({:new_date_idea, doc}, socket) do
    push(socket, "new_date_idea", doc)
    {:noreply, socket}
  end

  def handle_info({:date_idea_updated, doc}, socket) do
    push(socket, "date_idea_updated", doc)
    {:noreply, socket}
  end

  def handle_info({:date_idea_deleted, payload}, socket) do
    push(socket, "date_idea_deleted", payload)
    {:noreply, socket}
  end
end
