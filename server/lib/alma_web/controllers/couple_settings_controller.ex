defmodule AlmaWeb.CoupleSettingsController do
  @moduledoc """
  Read and write per-couple visual preferences (background_url, theme tint).
  Broadcasts changes on `couple:<id>` so the partner's app refreshes live.
  """
  use Phoenix.Controller, formats: [:json]

  alias Alma.MongoClient

  @coll "couple_settings"

  def show(conn, _params) do
    user = conn.assigns.current_user

    case user["couple_id"] do
      nil -> json(conn, %{settings: nil})
      couple_id -> json(conn, %{settings: load(couple_id)})
    end
  end

  def update(conn, params) do
    user = conn.assigns.current_user

    case user["couple_id"] do
      nil ->
        conn |> put_status(:bad_request) |> json(%{error: "not_linked"})

      couple_id ->
        patch =
          %{}
          |> maybe_put("background_url", params["background_url"])
          |> maybe_put("tint", params["tint"])
          |> Map.put("updated_at", DateTime.utc_now())

        MongoClient.update(@coll, %{"couple_id" => couple_id}, patch)
        settings = load(couple_id)

        Phoenix.PubSub.broadcast(
          Alma.PubSub,
          "couple:#{couple_id}",
          {:settings_updated, settings}
        )

        json(conn, %{settings: settings})
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp load(couple_id) do
    case MongoClient.find_one(@coll, %{"couple_id" => couple_id}) do
      nil ->
        %{"couple_id" => couple_id, "background_url" => nil, "tint" => nil}

      doc ->
        %{
          "couple_id" => doc["couple_id"],
          "background_url" => doc["background_url"],
          "tint" => doc["tint"],
          "started_at" => doc["started_at"],
          "updated_at" => doc["updated_at"]
        }
    end
  end
end
