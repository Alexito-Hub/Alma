defmodule AlmaWeb.DateIdeaController do
  use Phoenix.Controller, formats: [:json]
  alias Alma.DateIdeas

  def index(conn, _params) do
    cid = conn.assigns.current_user["couple_id"]
    json(conn, %{date_ideas: DateIdeas.list_for_couple(cid)})
  end

  def create(conn, params) do
    case DateIdeas.create(conn.assigns.current_user, params) do
      {:ok, doc} -> conn |> put_status(:created) |> json(%{date_idea: doc})
      err -> conn |> put_status(:bad_request) |> json(%{error: inspect(err)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case DateIdeas.update(conn.assigns.current_user, id, params) do
      {:ok, doc} -> json(conn, %{date_idea: doc})
      {:error, _} -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  def delete(conn, %{"id" => id}) do
    case DateIdeas.delete(conn.assigns.current_user, id) do
      :ok -> json(conn, %{ok: true})
      {:error, _} -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end
end
