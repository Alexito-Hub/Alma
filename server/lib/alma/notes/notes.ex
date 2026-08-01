defmodule Alma.Notes do
  alias Alma.MongoClient
  @coll "notes"

  @doc """
  Create a diary note. `attrs` is the note map sent by the client and may carry
  the Diary 2.0 rich fields (mood, link, image_urls, video_url, geotag,
  reaction) — all optional. Only `body` is meaningful-required.

  Idempotent per (author, client_id): a re-send after a lost ack returns the
  already-stored note instead of inserting a duplicate.
  """
  def create(author, attrs) when is_map(attrs) do
    client_id = attrs["client_id"] && to_string(attrs["client_id"])

    case existing(author, client_id) do
      nil ->
        doc = %{
          "client_id" => client_id,
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

      doc ->
        # Already stored (retry after a lost ack) — no insert, no re-broadcast.
        {:ok, doc}
    end
  end

  def list_for_couple(couple_id) do
    MongoClient.find(@coll, %{"couple_id" => couple_id}, sort: %{"created_at" => -1}, limit: 500)
  end

  @doc """
  Author-only text edit. Always sets body/mood/link from `attrs` (clients send
  all three, using nil to clear). Broadcasts so the partner's diary updates.
  """
  def update(user, id, attrs) do
    with {:ok, oid} <- object_id(id),
         {:ok, %Mongo.UpdateResult{matched_count: 1}} <-
           Mongo.update_one(
             :mongo,
             @coll,
             %{"_id" => oid, "author_id" => user["_id"]},
             %{
               "$set" => %{
                 "body" => attrs["body"] || "",
                 "mood" => attrs["mood"],
                 "link" => attrs["link"]
               }
             }
           ) do
      doc = MongoClient.find_one(@coll, %{"_id" => id})

      if cid = user["couple_id"] do
        Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{cid}", {:note_updated, doc})
      end

      {:ok, doc}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Author-only delete. Broadcasts so the entry disappears live for the partner."
  def delete(user, id) do
    with {:ok, oid} <- object_id(id),
         {:ok, %Mongo.DeleteResult{deleted_count: 1}} <-
           Mongo.delete_one(:mongo, @coll, %{"_id" => oid, "author_id" => user["_id"]}) do
      if cid = user["couple_id"] do
        Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{cid}", {:note_deleted, %{"id" => id}})
      end

      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  defp object_id(id) do
    {:ok, BSON.ObjectId.decode!(id)}
  rescue
    _ -> {:error, :invalid_id}
  end

  defp existing(_author, nil), do: nil

  defp existing(author, client_id) do
    MongoClient.find_one(@coll, %{"author_id" => author["_id"], "client_id" => client_id})
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
