defmodule Alma.Posts do
  alias Alma.MongoClient

  @coll "posts"
  @comments "comments"

  @doc """
  Idempotent per (author, client_id): a re-send after a lost ack returns the
  already-stored post instead of inserting a duplicate.
  """
  def create(author, attrs) do
    client_id = attrs["client_id"] && to_string(attrs["client_id"])

    case existing(author, client_id) do
      nil ->
        doc = %{
          "client_id" => client_id,
          "title" => attrs["title"] || "",
          "description" => attrs["description"] || "",
          "media_urls" => attrs["media_urls"] || [],
          "tags" => attrs["tags"] || [],
          # Private posts only surface in the app's PIN-gated view.
          "private" => attrs["private"] == true,
          # Optional geotag: coordinates plus the label shown in the feed.
          "latitude" => attrs["latitude"],
          "longitude" => attrs["longitude"],
          "place_label" => attrs["place_label"],
          "author_id" => author["_id"],
          "couple_id" => author["couple_id"],
          "created_at" => parse_dt(attrs["created_at"]),
          "comment_count" => 0
        }

        with {:ok, id} <- MongoClient.insert(@coll, doc) do
          {:ok, Map.put(doc, "_id", id)}
        end

      doc ->
        {:ok, doc}
    end
  end

  defp existing(_author, nil), do: nil

  defp existing(author, client_id) do
    MongoClient.find_one(@coll, %{"author_id" => author["_id"], "client_id" => client_id})
  end

  def list_for_couple(couple_id) do
    MongoClient.find(@coll, %{"couple_id" => couple_id}, sort: %{"created_at" => -1}, limit: 100)
  end

  @doc "Author-only text edit (title/description/tags). Broadcasts to the couple."
  def update(user, id, attrs) do
    with {:ok, oid} <- object_id(id),
         {:ok, %Mongo.UpdateResult{matched_count: 1}} <-
           Mongo.update_one(
             :mongo,
             @coll,
             %{"_id" => oid, "author_id" => user["_id"]},
             %{
               "$set" => %{
                 "title" => attrs["title"] || "",
                 "description" => attrs["description"] || "",
                 "tags" => attrs["tags"] || []
               }
             }
           ) do
      doc = MongoClient.find_one(@coll, %{"_id" => id})

      if cid = user["couple_id"] do
        Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{cid}", {:post_updated, doc})
      end

      {:ok, doc}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Author-only delete; removes the post's comments too. Broadcasts to the couple."
  def delete(user, id) do
    with {:ok, oid} <- object_id(id),
         {:ok, %Mongo.DeleteResult{deleted_count: 1}} <-
           Mongo.delete_one(:mongo, @coll, %{"_id" => oid, "author_id" => user["_id"]}) do
      Mongo.delete_many(:mongo, @comments, %{"post_id" => id})

      if cid = user["couple_id"] do
        Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{cid}", {:post_deleted, %{"id" => id}})
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

  def get(id), do: MongoClient.find_one(@coll, %{"_id" => id})

  def add_comment(post_id, author, text) do
    doc = %{
      "post_id" => post_id,
      "author_id" => author["_id"],
      "author_email" => author["email"],
      "body" => text,
      "created_at" => DateTime.utc_now()
    }

    with {:ok, id} <- MongoClient.insert(@comments, doc) do
      Mongo.update_one(:mongo, @coll, %{"_id" => BSON.ObjectId.decode!(post_id)}, %{
        "$inc" => %{"comment_count" => 1}
      })

      {:ok, Map.put(doc, "_id", id) |> public_comment()}
    end
  end

  def list_comments(post_id) do
    MongoClient.find(@comments, %{"post_id" => post_id}, sort: %{"created_at" => 1})
    |> Enum.map(&public_comment/1)
  end

  defp public_comment(c) do
    %{
      "id" => c["_id"],
      "post_id" => c["post_id"],
      "author_id" => c["author_id"],
      "author_email" => c["author_email"],
      "body" => c["body"] || c["text"],
      "created_at" => c["created_at"]
    }
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
