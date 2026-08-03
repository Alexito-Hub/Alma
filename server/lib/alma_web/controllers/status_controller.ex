defmodule AlmaWeb.StatusController do
  use Phoenix.Controller, formats: [:json]
  alias Alma.Statuses

  def update(conn, %{"text" => text} = params) do
    {:ok, payload} =
      Statuses.update(conn.assigns.current_user, text, params["image_url"])

    json(conn, %{status: payload})
  end

  def show(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      status: Statuses.show(user),
      statuses: Statuses.list_for_couple(user)
    })
  end
end
