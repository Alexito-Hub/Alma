defmodule AlmaWeb.CoupleRequestController do
  use Phoenix.Controller, formats: [:json]

  alias Alma.Accounts
  alias Alma.Couples.Requests

  def create(conn, params) do
    user = conn.assigns.current_user
    code = params["code"] || params["to_code"] || ""

    case Requests.create(user, code, params) do
      {:ok, request} -> json(conn, %{request: Requests.to_public(request)})
      {:error, reason} -> bad(conn, reason)
    end
  end

  def index(conn, params) do
    user = conn.assigns.current_user

    requests =
      case params["type"] do
        "sent" -> Requests.list_sent(user)
        _ -> Requests.list_received(user)
      end

    json(conn, %{
      requests: requests,
      me_code: Requests.code_for(user)
    })
  end

  def accept(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Requests.accept(user, id) do
      {:ok, updated_user} -> json(conn, %{user: Accounts.to_public(updated_user)})
      {:error, reason} -> bad(conn, reason)
    end
  end

  def reject(conn, %{"id" => id}) do
    case Requests.reject(conn.assigns.current_user, id) do
      :ok -> json(conn, %{ok: true})
      {:error, reason} -> bad(conn, reason)
    end
  end

  def cancel(conn, %{"id" => id}) do
    case Requests.cancel(conn.assigns.current_user, id) do
      :ok -> json(conn, %{ok: true})
      {:error, reason} -> bad(conn, reason)
    end
  end

  defp bad(conn, reason) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: to_string(reason)})
  end
end
