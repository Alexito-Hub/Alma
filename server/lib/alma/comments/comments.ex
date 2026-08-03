defmodule Alma.Comments do
  @moduledoc """
  Comments on a diary entry.

  Stored in the same `comments` collection the feed used, but keyed by
  `target_type` + `target_id` so a thread can hang off anything. Existing feed
  rows (which only carry `post_id`) are left untouched — they're read by the
  older `Alma.Posts` functions.

  Broadcasts on the couple channel so the other phone sees a reply appear
  without opening anything.

  Everything here is gated on `visible?/3`. Comments used to be the one route
  in the API that didn't filter by couple: any authenticated account could
  read or write a thread on any id it could name. With two users that leaked
  nothing, but it was the single place where `couple_id` wasn't the boundary,
  so it is the place a third account would have walked in.
  """
  alias Alma.MongoClient

  @coll "comments"

  @doc """
  Whether `user` may read and write this thread.

  True when the target exists and belongs to the user's couple. An unlinked
  user is limited to their own documents — never to every other unlinked
  user's, which a bare `couple_id == nil` comparison would have allowed.
  """
  def visible?(user, target_type, target_id) do
    case target_doc(target_type, target_id) do
      nil -> false
      doc -> same_couple?(user, doc)
    end
  end

  def add(user, target_type, target_id, text) do
    if visible?(user, target_type, target_id) do
      doc = %{
        "target_type" => target_type,
        "target_id" => target_id,
        "couple_id" => user["couple_id"],
        "author_id" => user["_id"],
        "author_email" => user["email"],
        "body" => text,
        "created_at" => DateTime.utc_now()
      }

      with {:ok, id} <- MongoClient.insert(@coll, doc) do
        stored = Map.put(doc, "_id", id)

        if cid = user["couple_id"] do
          Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{cid}", {:new_comment, stored})
        end

        {:ok, stored}
      end
    else
      {:error, :not_found}
    end
  end

  def list(user, target_type, target_id) do
    if visible?(user, target_type, target_id) do
      MongoClient.find(
        @coll,
        %{"target_type" => target_type, "target_id" => target_id},
        sort: %{"created_at" => 1},
        limit: 500
      )
    else
      []
    end
  end

  @doc "Remove every comment hanging off a target (used when it's deleted)."
  def delete_for(target_type, target_id) do
    Mongo.delete_many(:mongo, @coll, %{
      "target_type" => target_type,
      "target_id" => target_id
    })
  end

  defp target_doc("note", id), do: MongoClient.find_one("notes", %{"_id" => id})
  defp target_doc("post", id), do: MongoClient.find_one("posts", %{"_id" => id})
  defp target_doc(_type, _id), do: nil

  defp same_couple?(%{"couple_id" => cid}, %{"couple_id" => cid})
       when is_binary(cid) and cid != "",
       do: true

  defp same_couple?(user, doc), do: doc["author_id"] == user["_id"]
end
