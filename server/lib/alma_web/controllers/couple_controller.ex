defmodule AlmaWeb.CoupleController do
  use Phoenix.Controller, formats: [:json]
  alias Alma.{Couples, Accounts}

  def link(conn, %{"code" => code}) do
    case Couples.link(conn.assigns.current_user, code) do
      {:ok, user} ->
        json(conn, %{user: Accounts.to_public(user)})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
    end
  end
end
