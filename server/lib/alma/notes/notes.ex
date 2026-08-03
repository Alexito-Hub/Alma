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
          "private" => attrs["private"] == true,
          "mood" => attrs["mood"],
          "link" => attrs["link"],
          "image_urls" => attrs["image_urls"] || [],
          "video_urls" => attrs["video_urls"] || [],
          "video_url" => attrs["video_url"],
          "audio_url" => attrs["audio_url"],
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
  Edit an entry.

  An entry has two owners, not one. The **body** (with its mood and link)
  belongs to whoever wrote it; the **reaction** belongs to whoever left it,
  and leaving one is the whole point of reacting to your partner's memory.
  Enforcing a single author-only filter over both meant a reaction from the
  partner matched nothing and was dropped, so the two halves are applied as
  two separately scoped updates: the body filtered by `author_id`, the
  reaction by `couple_id`.

  Each half is only touched when the client actually sent it, so a partner's
  reaction PUT (which omits the text) can't blank a body, and neither can it
  slip a rewrite past the author check.

  Succeeds when either half applied; broadcasts once so the other phone
  updates live.
  """
  def update(user, id, attrs) do
    case MongoClient.object_id(id) do
      :error ->
        {:error, :not_found}

      {:ok, oid} ->
        # Both halves are evaluated: an author who edits the text *and* leaves
        # a reaction in the same PUT must get both applied, so these must not
        # collapse into a short-circuiting `or`.
        text_applied = set_scoped(oid, %{"author_id" => user["_id"]}, text_changes(attrs))
        reaction_applied = set_scoped(oid, couple_scope(user), reaction_changes(attrs))

        if text_applied or reaction_applied do
          doc = MongoClient.find_one(@coll, %{"_id" => id})

          if cid = user["couple_id"] do
            Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{cid}", {:note_updated, doc})
          end

          {:ok, doc}
        else
          {:error, :not_found}
        end
    end
  end

  # The fields the author owns, and only those the client actually sent.
  defp text_changes(attrs) do
    Enum.reduce(["body", "mood", "link"], %{}, fn key, acc ->
      if Map.has_key?(attrs, key), do: Map.put(acc, key, attrs[key]), else: acc
    end)
  end

  # The reaction travels as a pair; an emoji of nil clears it.
  defp reaction_changes(attrs) do
    if Map.has_key?(attrs, "reaction_emoji") do
      %{
        "reaction_emoji" => attrs["reaction_emoji"],
        "reaction_author_id" => attrs["reaction_author_id"]
      }
    else
      %{}
    end
  end

  # An unlinked user has no couple to scope by; fall back to their own docs
  # rather than to a filter that would match every unlinked user's entries.
  defp couple_scope(%{"couple_id" => cid} = _user) when is_binary(cid) and cid != "",
    do: %{"couple_id" => cid}

  defp couple_scope(user), do: %{"author_id" => user["_id"]}

  # Applies `changes` to the doc if `scope` matches it. True when it did.
  defp set_scoped(_oid, _scope, changes) when map_size(changes) == 0, do: false

  defp set_scoped(oid, scope, changes) do
    filter = Map.put(scope, "_id", oid)

    case Mongo.update_one(:mongo, @coll, filter, %{"$set" => changes}) do
      {:ok, %Mongo.UpdateResult{matched_count: 1}} -> true
      _ -> false
    end
  end

  @doc """
  Author-only delete, including the entry's photos, clips and voice note.
  Broadcasts so it disappears live for the partner.
  """
  def delete(user, id) do
    # Read the doc first: once it's gone we can't tell which files were its.
    doc = MongoClient.find_one(@coll, %{"_id" => id})

    with {:ok, oid} <- MongoClient.object_id(id),
         {:ok, %Mongo.DeleteResult{deleted_count: 1}} <-
           Mongo.delete_one(:mongo, @coll, %{"_id" => oid, "author_id" => user["_id"]}) do
      if doc do
        Alma.Media.delete_urls([
          doc["image_urls"],
          doc["video_urls"],
          doc["video_url"],
          doc["audio_url"]
        ])
      end

      Alma.Comments.delete_for("note", id)

      if cid = user["couple_id"] do
        Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{cid}", {:note_deleted, %{"id" => id}})
      end

      :ok
    else
      _ -> {:error, :not_found}
    end
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
