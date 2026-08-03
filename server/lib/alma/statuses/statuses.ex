defmodule Alma.Statuses do
  @moduledoc """
  Each user has a single, mutable "current status" — a short line about how
  they feel, optionally with a snapshot taken at that moment. We store it on
  the user doc itself (`current_status`, `current_status_image`,
  `status_updated_at`); no separate collection is needed since we only ever
  read the latest value.

  Updates broadcast via PubSub to the couple's channel.
  """
  alias Alma.Accounts

  def update(user, text, image_url \\ nil) do
    now = DateTime.utc_now()
    previous = user["current_status_image"]

    :ok =
      Accounts.update_user(user["_id"], %{
        "current_status" => text,
        "current_status_image" => image_url,
        "status_updated_at" => now
      })

    # A status is a snapshot of *now*: only the current photo is kept, so the
    # one it replaces is deleted instead of piling up on disk forever.
    if is_binary(previous) and previous != image_url do
      Alma.Media.delete_urls(previous)
    end

    payload = %{
      "author_id" => user["_id"],
      "text" => text,
      "image_url" => image_url,
      "updated_at" => DateTime.to_iso8601(now)
    }

    if user["couple_id"] do
      Phoenix.PubSub.broadcast(
        Alma.PubSub,
        "couple:#{user["couple_id"]}",
        {:status_updated, payload}
      )
    end

    {:ok, payload}
  end

  def show(user) do
    to_payload(user)
  end

  @doc """
  All status payloads for the couple (so a freshly-installed client can
  hydrate both bubbles in one round-trip).
  """
  def list_for_couple(user) do
    case user["couple_id"] do
      nil ->
        [to_payload(user)]

      cid ->
        Alma.MongoClient.find("users", %{"couple_id" => cid}, limit: 2)
        |> Enum.map(&to_payload/1)
    end
  end

  defp to_payload(user) do
    %{
      "author_id" => user["_id"],
      "text" => user["current_status"] || "",
      "image_url" => user["current_status_image"],
      "updated_at" => (user["status_updated_at"] || DateTime.utc_now()) |> DateTime.to_iso8601()
    }
  end
end
