defmodule Alma.SpecialDates do
  @moduledoc """
  A couple's special dates (anniversaries, birthdays, trips…). Stored in the
  `special_dates` Mongo collection, partitioned by `couple_id` like everything
  else. Broadcasts creations on the couple channel so the partner's calendar
  updates live.
  """
  alias Alma.MongoClient

  @coll "special_dates"

  def create(author, attrs) do
    doc = %{
      "couple_id" => author["couple_id"],
      "author_id" => author["_id"],
      "title" => attrs["title"] || "",
      "emoji" => attrs["emoji"],
      "recurring" => attrs["recurring"] != false,
      "date" => parse_dt(attrs["date"]),
      "created_at" => DateTime.utc_now()
    }

    with {:ok, id} <- MongoClient.insert(@coll, doc) do
      stored = Map.put(doc, "_id", id)

      if cid = author["couple_id"] do
        Phoenix.PubSub.broadcast(Alma.PubSub, "couple:#{cid}", {:new_special_date, stored})
      end

      {:ok, stored}
    end
  end

  def list_for_couple(couple_id) do
    MongoClient.find(@coll, %{"couple_id" => couple_id}, sort: %{"date" => 1}, limit: 500)
  end

  @doc "Delete a special date scoped to the caller's couple."
  def delete(couple_id, id) when is_binary(id) do
    Mongo.delete_one(:mongo, @coll, %{
      "_id" => BSON.ObjectId.decode!(id),
      "couple_id" => couple_id
    })
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
