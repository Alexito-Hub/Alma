defmodule AlmaWeb.SpecialDateController do
  use Phoenix.Controller, formats: [:json]
  alias Alma.SpecialDates

  def index(conn, _params) do
    cid = conn.assigns.current_user["couple_id"]
    json(conn, %{special_dates: SpecialDates.list_for_couple(cid)})
  end

  def create(conn, params) do
    case SpecialDates.create(conn.assigns.current_user, params) do
      {:ok, doc} -> conn |> put_status(:created) |> json(%{special_date: doc})
      err -> conn |> put_status(:bad_request) |> json(%{error: inspect(err)})
    end
  end

  def delete(conn, %{"id" => id}) do
    SpecialDates.delete(conn.assigns.current_user["couple_id"], id)
    json(conn, %{ok: true})
  end
end
