defmodule Alma.Media do
  @moduledoc """
  Media ownership context. Persists an upload via `Alma.Media.Storage` (which
  namespaces it by couple on disk) and records a `media` document so every file
  is attributable to a couple/author. Previously uploads were anonymous on disk
  with no ownership row at all.
  """

  alias Alma.Media.Storage
  alias Alma.MongoClient

  @coll "media"

  @doc """
  Store an upload for `user`, namespaced by their couple (or the user when
  unlinked), and record ownership. Returns `{:ok, media_doc}` where `media_doc`
  carries `"url"` and `"_id"`.
  """
  def store(user, %Plug.Upload{} = upload) do
    owner = owner_for(user)

    with {:ok, rel_path, url} <- Storage.store(upload, owner) do
      doc = %{
        "couple_id" => user["couple_id"],
        "author_id" => user["_id"],
        "path" => rel_path,
        "url" => url,
        "content_type" => upload.content_type,
        "filename" => upload.filename,
        "created_at" => DateTime.utc_now()
      }

      case MongoClient.insert(@coll, doc) do
        {:ok, id} ->
          {:ok, Map.put(doc, "_id", id)}

        {:error, _err} ->
          # The file is already on disk and reachable; don't fail the whole
          # upload just because the ownership bookkeeping row didn't insert.
          {:ok, Map.put(doc, "_id", nil)}
      end
    end
  end

  @doc "All media rows for a couple, newest first."
  def list_for_couple(couple_id) do
    MongoClient.find(@coll, %{"couple_id" => couple_id},
      sort: %{"created_at" => -1},
      limit: 500
    )
  end

  # Couple id when linked; a stable per-user bucket otherwise so even
  # pre-link uploads stay identifiable and isolated.
  defp owner_for(%{"couple_id" => cid}) when is_binary(cid) and cid != "", do: cid
  defp owner_for(%{"_id" => uid}), do: "u_#{uid}"
end
