defmodule Alma.Posts do
  alias Alma.MongoClient

  @coll "posts"
  @comments "comments"

  def create(author, attrs) do
    doc = %{
      "title" => attrs["title"] || "",
      "description" => attrs["description"] || "",
      "media_urls" => attrs["media_urls"] || [],
      "tags" => attrs["tags"] || [],
      "author_id" => author["_id"],
      "couple_id" => author["couple_id"],
      "created_at" => parse_dt(attrs["created_at"]),
      "comment_count" => 0
    }

    with {:ok, id} <- MongoClient.insert(@coll, doc) do
      {:ok, Map.put(doc, "_id", id)}
    end
  end

  def list_for_couple(couple_id) do
    MongoClient.find(@coll, %{"couple_id" => couple_id}, sort: %{"created_at" => -1}, limit: 100)
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
