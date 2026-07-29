defmodule AlmaWeb.AuthController do
  use Phoenix.Controller, formats: [:json]

  alias Alma.{Accounts, Guardian}

  def register(conn, %{"email" => email, "password" => password}) do
    case Accounts.register(email, password) do
      {:ok, user} -> issue(conn, user)
      {:error, reason} -> bad(conn, reason)
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate(email, password) do
      {:ok, user} -> issue(conn, user)
      {:error, reason} -> bad(conn, reason)
    end
  end

  def me(conn, _params) do
    user = conn.assigns.current_user
    partner = lookup_partner(user)

    json(conn, %{
      user: Accounts.to_public(user),
      partner: if(partner, do: Accounts.to_public(partner))
    })
  end

  def update_avatar(conn, %{"avatar_url" => url}) do
    update_profile(conn, %{"avatar_url" => url})
  end

  def update_profile(conn, params) do
    user = conn.assigns.current_user

    patch =
      %{}
      |> maybe_put("avatar_url", params["avatar_url"])
      |> maybe_put("display_name", params["display_name"])

    if patch == %{} do
      bad(conn, :nothing_to_update)
    else
      Accounts.update_user(user["_id"], patch)
      fresh = Accounts.get_user(user["_id"])

      if cid = user["couple_id"] do
        Phoenix.PubSub.broadcast(
          Alma.PubSub,
          "couple:#{cid}",
          {:partner_updated, Map.put(patch, "user_id", user["_id"])}
        )
      end

      json(conn, %{user: Accounts.to_public(fresh)})
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp lookup_partner(user) do
    case user["couple_id"] do
      nil ->
        nil

      cid ->
        Alma.MongoClient.find("users", %{"couple_id" => cid}, limit: 2)
        |> Enum.find(fn u -> u["_id"] != user["_id"] end)
    end
  end

  defp issue(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user, %{}, ttl: {30, :days})
    json(conn, %{token: token, user: Accounts.to_public(user)})
  end

  defp bad(conn, reason) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: to_string(reason)})
  end
end
