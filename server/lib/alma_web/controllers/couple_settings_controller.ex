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

  # ── Private-feed PIN (couple-shared, stored as a Bcrypt hash) ─────────────

  def pin_status(conn, _params) do
    json(conn, %{set: pin_hash(conn) != nil})
  end

  def set_pin(conn, %{"pin" => pin}) when is_binary(pin) do
    user = conn.assigns.current_user

    cond do
      user["couple_id"] == nil ->
        conn |> put_status(:bad_request) |> json(%{error: "not_linked"})

      String.length(pin) < 4 ->
        conn |> put_status(:bad_request) |> json(%{error: "pin_too_short"})

      true ->
        MongoClient.update(@coll, %{"couple_id" => user["couple_id"]}, %{
          "couple_id" => user["couple_id"],
          "pin_hash" => Bcrypt.hash_pwd_salt(pin)
        })

        json(conn, %{ok: true})
    end
  end

  # Four digits is 10.000 combinations — cheap to walk through unless trying
  # costs something. Five wrong answers freeze the couple's PIN for a while;
  # a correct one clears the counter, so the two of them never notice.
  @pin_max_attempts 5
  @pin_window_seconds 300

  def verify_pin(conn, %{"pin" => pin}) when is_binary(pin) do
    user = conn.assigns.current_user
    key = {:pin, user["couple_id"] || user["_id"]}

    case Alma.Throttle.check(key, @pin_max_attempts, @pin_window_seconds) do
      {:blocked, seconds} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{ok: false, error: "too_many_attempts", retry_after: seconds})

      :ok ->
        hash = pin_hash(conn)

        if is_binary(hash) and Bcrypt.verify_pass(pin, hash) do
          Alma.Throttle.reset(key)
          json(conn, %{ok: true})
        else
          Alma.Throttle.fail(key)
          json(conn, %{ok: false})
        end
    end
  end

  defp pin_hash(conn) do
    case conn.assigns.current_user["couple_id"] do
      nil ->
        nil

      cid ->
        case MongoClient.find_one(@coll, %{"couple_id" => cid}) do
          nil -> nil
          doc -> doc["pin_hash"]
        end
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
