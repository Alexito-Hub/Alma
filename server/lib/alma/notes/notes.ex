defmodule Alma.Notes do
  alias Alma.MongoClient
  @coll "notes"

  @doc """
  Create a diary note. `attrs` is the note map sent by the client and may carry
  the Diary 2.0 rich fields (mood, link, image_urls, video_url, geotag,
  reaction) — all optional. Only `body` is meaningful-required.
  """
  def create(author, attrs) when is_map(attrs) do
    doc = %{
      "body" => attrs["body"] || "",
      "author_id" => author["_id"],
      "couple_id" => author["couple_id"],
      "created_at" => parse_dt(attrs["created_at"]),
      "mood" => attrs["mood"],
      "link" => attrs["link"],
      "image_urls" => attrs["image_urls"] || [],
      "video_url" => attrs["video_url"],
      "latitude" => attrs["latitude"],
      "longitude" => attrs["longitude"],
      "place_label" => attrs["place_label"],
      "reaction_emoji" => attrs["reaction_emoji"],
      "reaction_author_id" => attrs["reaction_author_id"]
    }

    with {:ok, id} <- MongoClient.insert(@coll, doc) do
      stored = Map.put(doc, "_id", id)

      if cid = author["couple_id"] do
        Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{cid}", {:new_note, stored})
      end

      {:ok, stored}
    end
  end

  def list_for_couple(couple_id) do
    MongoClient.find(@coll, %{"couple_id" => couple_id}, sort: %{"created_at" => -1}, limit: 500)
  end

  defp parse_dt(nil), do: DateTime.utc_now()
  defp parse_dt(%DateTime{} = dt), do: dt

  defp parse_dt(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
end
