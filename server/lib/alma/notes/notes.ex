defmodule Alma.Notes do
  alias Alma.MongoClient
  @coll "notes"

  def create(author, body, created_at \\ nil) do
    doc = %{
      "body" => body,
      "author_id" => author["_id"],
      "couple_id" => author["couple_id"],
      "created_at" => parse_dt(created_at)
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
