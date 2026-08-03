defmodule Alma.DateIdeas do
  @moduledoc """
  "Citas": places the couple wants to go, and the ones they already went to.

  Shared rather than owned — either partner can propose one, edit it or mark it
  as lived, so everything here is scoped by `couple_id` instead of `author_id`.
  Creation is idempotent per (author, client_id) like the rest of the sync.
  """
  alias Alma.MongoClient

  @coll "date_ideas"

  def create(author, attrs) do
    client_id = attrs["client_id"] && to_string(attrs["client_id"])

    case existing(author, client_id) do
      nil ->
        doc = %{
          "client_id" => client_id,
          "couple_id" => author["couple_id"],
          "author_id" => author["_id"],
          "title" => attrs["title"] || "",
          "description" => attrs["description"] || "",
          "planned_at" => parse_dt(attrs["planned_at"]),
          "done" => attrs["done"] == true,
          "done_at" => parse_dt(attrs["done_at"]),
          "done_note" => attrs["done_note"],
          "image_urls" => attrs["image_urls"] || [],
          "latitude" => attrs["latitude"],
          "longitude" => attrs["longitude"],
          "place_label" => attrs["place_label"],
          "created_at" => parse_dt(attrs["created_at"]) || DateTime.utc_now()
        }

        with {:ok, id} <- MongoClient.insert(@coll, doc) do
          stored = Map.put(doc, "_id", id)
          broadcast(author["couple_id"], {:new_date_idea, stored})
          {:ok, stored}
        end

      doc ->
        {:ok, doc}
    end
  end

  def list_for_couple(couple_id) do
    MongoClient.find(@coll, %{"couple_id" => couple_id},
      sort: %{"created_at" => -1},
      limit: 500
    )
  end

  @doc "Update a shared idea. Any member of the couple may edit it."
  def update(user, id, attrs) do
    with {:ok, oid} <- MongoClient.object_id(id),
         {:ok, %Mongo.UpdateResult{matched_count: 1}} <-
           Mongo.update_one(
             :mongo,
             @coll,
             %{"_id" => oid, "couple_id" => user["couple_id"]},
             %{
               "$set" => %{
                 "title" => attrs["title"] || "",
                 "description" => attrs["description"] || "",
                 "planned_at" => parse_dt(attrs["planned_at"]),
                 "done" => attrs["done"] == true,
                 "done_at" => parse_dt(attrs["done_at"]),
                 "done_note" => attrs["done_note"],
                 "image_urls" => attrs["image_urls"] || [],
                 "latitude" => attrs["latitude"],
                 "longitude" => attrs["longitude"],
                 "place_label" => attrs["place_label"]
               }
             }
           ) do
      doc = MongoClient.find_one(@coll, %{"_id" => id})
      broadcast(user["couple_id"], {:date_idea_updated, doc})
      {:ok, doc}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Delete a shared idea and any photos attached to it."
  def delete(user, id) do
    doc = MongoClient.find_one(@coll, %{"_id" => id})

    with {:ok, oid} <- MongoClient.object_id(id),
         {:ok, %Mongo.DeleteResult{deleted_count: 1}} <-
           Mongo.delete_one(:mongo, @coll, %{
             "_id" => oid,
             "couple_id" => user["couple_id"]
           }) do
      if doc, do: Alma.Media.delete_urls(doc["image_urls"])
      broadcast(user["couple_id"], {:date_idea_deleted, %{"id" => id}})
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  defp broadcast(nil, _msg), do: :ok

  defp broadcast(couple_id, msg) do
    Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{couple_id}", msg)
  end

  defp existing(_author, nil), do: nil

  defp existing(author, client_id) do
    MongoClient.find_one(@coll, %{
      "author_id" => author["_id"],
      "client_id" => client_id
    })
  end

  defp parse_dt(nil), do: nil
  defp parse_dt(%DateTime{} = dt), do: dt

  defp parse_dt(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_dt(_), do: nil
end
