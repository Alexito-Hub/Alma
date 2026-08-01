defmodule Alma.MongoIndexes do
  @moduledoc """
  Ensures the indexes every hot query relies on exist. Runs once at boot as a
  fire-and-forget task; `createIndexes` is idempotent, and any failure is
  logged without touching app startup.

  Covers: per-couple listings (notes/posts/special_dates/media), the
  (author, client_id) idempotency lookups used to dedupe re-sends, comment
  threads, and user lookups by email/couple.
  """
  require Logger

  def ensure do
    create("users", [
      %{"key" => %{"email" => 1}, "name" => "email_idx"},
      %{"key" => %{"couple_id" => 1}, "name" => "couple_idx"}
    ])

    create("notes", [
      %{"key" => %{"couple_id" => 1, "created_at" => -1}, "name" => "couple_created_idx"},
      %{"key" => %{"author_id" => 1, "client_id" => 1}, "name" => "author_client_idx"}
    ])

    create("posts", [
      %{"key" => %{"couple_id" => 1, "created_at" => -1}, "name" => "couple_created_idx"},
      %{"key" => %{"author_id" => 1, "client_id" => 1}, "name" => "author_client_idx"}
    ])

    create("special_dates", [
      %{"key" => %{"couple_id" => 1, "date" => 1}, "name" => "couple_date_idx"},
      %{"key" => %{"author_id" => 1, "client_id" => 1}, "name" => "author_client_idx"}
    ])

    create("comments", [
      %{"key" => %{"post_id" => 1, "created_at" => 1}, "name" => "post_created_idx"}
    ])

    create("media", [
      %{"key" => %{"couple_id" => 1, "created_at" => -1}, "name" => "couple_created_idx"}
    ])

    :ok
  end

  defp create(coll, indexes) do
    Mongo.command(:mongo, [createIndexes: coll, indexes: indexes], [])
    :ok
  rescue
    e -> Logger.warning("index creation for #{coll} failed: #{inspect(e)}")
  catch
    :exit, reason -> Logger.warning("index creation for #{coll} exited: #{inspect(reason)}")
  end
end
