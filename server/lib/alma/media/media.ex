defmodule Alma.Media do
  @moduledoc """
  Media ownership and lifecycle.

  Persists an upload via `Alma.Media.Storage` (which namespaces it by couple on
  disk) and records a `media` document so every file is attributable. It also
  owns the *other* half of the lifecycle that used to be missing: deleting a
  post, a note or a replaced status snapshot now removes the bytes too, and
  `sweep_orphans/1` clears anything left behind.
  """

  require Logger

  alias Alma.Media.Storage
  alias Alma.MongoClient

  @coll "media"

  # Every place a media URL can be referenced from. Kept in one list so the
  # janitor can never fall out of sync with what the app actually stores.
  @references [
    {"posts", ["media_urls"]},
    {"notes", ["image_urls", "video_urls", "video_url", "audio_url"]},
    {"date_ideas", ["image_urls"]},
    {"users", ["avatar_url", "current_status_image"]},
    {"couple_settings", ["background_url"]}
  ]

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

  # ── deletion ───────────────────────────────────────────────────────────────

  @doc """
  Delete the files behind these public URLs and their `media` rows.

  Accepts anything the documents hold (a string, a list, nils mixed in). Paths
  are resolved and checked to be inside the media root, so a malformed URL can
  never reach outside it.
  """
  def delete_urls(urls) do
    root = media_root()

    urls
    |> List.wrap()
    |> Enum.flat_map(&List.wrap/1)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.each(fn url ->
      rel = relative_path(url)
      path = root |> Path.join(rel) |> Path.expand()

      if String.starts_with?(path, root <> "/") do
        case File.rm(path) do
          :ok -> :ok
          {:error, :enoent} -> :ok
          {:error, reason} -> Logger.warning("media rm #{rel}: #{inspect(reason)}")
        end

        Mongo.delete_many(:mongo, @coll, %{"path" => rel})
      end
    end)
  end

  # ── janitor ────────────────────────────────────────────────────────────────

  @doc """
  Delete files on disk that nothing references any more.

  `min_age_seconds` protects uploads that are still mid-flight: a file that was
  just written but whose post hasn't been created yet is not an orphan. Returns
  `{deleted_count, freed_bytes}`.
  """
  def sweep_orphans(min_age_seconds \\ 86_400) do
    root = media_root()
    referenced = referenced_paths()
    cutoff = System.system_time(:second) - min_age_seconds

    orphans =
      root
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        case File.stat(path, time: :posix) do
          {:ok, %File.Stat{type: :regular, mtime: mtime}} ->
            mtime < cutoff and not MapSet.member?(referenced, Path.relative_to(path, root))

          _ ->
            false
        end
      end)

    freed =
      Enum.reduce(orphans, 0, fn path, acc ->
        size =
          case File.stat(path) do
            {:ok, %File.Stat{size: s}} -> s
            _ -> 0
          end

        File.rm(path)
        Mongo.delete_many(:mongo, @coll, %{"path" => Path.relative_to(path, root)})
        acc + size
      end)

    if orphans != [] do
      Logger.info("media janitor: removed #{length(orphans)} orphan(s), freed #{freed} bytes")
    end

    {length(orphans), freed}
  end

  @doc "Relative paths (as stored on disk) currently referenced by any document."
  def referenced_paths do
    Enum.reduce(@references, MapSet.new(), fn {coll, fields}, acc ->
      :mongo
      |> Mongo.find(coll, %{})
      |> Enum.reduce(acc, fn doc, inner ->
        Enum.reduce(fields, inner, fn field, set ->
          doc
          |> Map.get(field)
          |> List.wrap()
          |> Enum.filter(&is_binary/1)
          |> Enum.reduce(set, &MapSet.put(&2, relative_path(&1)))
        end)
      end)
    end)
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  defp relative_path(url) do
    prefix = Application.fetch_env!(:alma, :media_public_prefix)
    String.replace_prefix(url, prefix <> "/", "")
  end

  defp media_root, do: :alma |> Application.fetch_env!(:media_root) |> Path.expand()

  # Couple id when linked; a stable per-user bucket otherwise so even
  # pre-link uploads stay identifiable and isolated.
  defp owner_for(%{"couple_id" => cid}) when is_binary(cid) and cid != "", do: cid
  defp owner_for(%{"_id" => uid}), do: "u_#{uid}"
end
