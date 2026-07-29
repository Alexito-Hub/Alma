defmodule Alma.Media.Storage do
  @moduledoc """
  Disk-backed media store. Files land under `media_root` from config, namespaced
  by owner so every couple's media lives in its own folder instead of a shared,
  unidentifiable date bucket:

      <media_root>/<owner>/<YYYY>/<MM>/<uuid>.<ext>

  `owner` is the couple id when the uploader is linked, otherwise `u_<user_id>`.
  The database only ever stores the *relative* path (e.g.
  `<owner>/2026/05/uuid.jpg`), which is later resolved to a public URL via
  `media_public_prefix`.
  """

  use Agent

  def child_spec do
    %{
      id: __MODULE__,
      start: {Agent, :start_link, [fn -> :ok end, [name: __MODULE__]]}
    }
  end

  @doc """
  Persist a `Plug.Upload` under `owner`'s folder.
  Returns `{:ok, relative_path, public_url}`.
  """
  def store(%Plug.Upload{} = upload, owner) when is_binary(owner) do
    ensure_root!()
    {dir, abs_dir} = dest_dir(owner)
    File.mkdir_p!(abs_dir)

    ext = upload.filename |> Path.extname() |> String.downcase()
    name = "#{UUID.uuid4()}#{ext}"

    abs_path = Path.join(abs_dir, name)
    rel_path = Path.join(dir, name)

    case File.cp(upload.path, abs_path) do
      :ok -> {:ok, rel_path, url_for(rel_path)}
      err -> err
    end
  end

  def url_for(rel_path) do
    prefix = Application.fetch_env!(:alma, :media_public_prefix)
    "#{prefix}/#{rel_path}"
  end

  # <owner>/<YYYY>/<MM>
  defp dest_dir(owner) do
    %Date{year: y, month: m} = Date.utc_today()
    dir = Path.join([sanitize(owner), "#{y}", String.pad_leading("#{m}", 2, "0")])
    {dir, Path.join(root(), dir)}
  end

  # Keep the owner segment to a safe, flat slug — guards against path traversal
  # or stray separators sneaking a file outside its bucket. couple UUIDs and
  # `u_<objectid>` both survive this untouched.
  defp sanitize(owner) do
    case String.replace(owner, ~r/[^a-zA-Z0-9_-]/, "") do
      "" -> "_shared"
      slug -> slug
    end
  end

  defp ensure_root! do
    File.mkdir_p!(root())
  end

  defp root, do: Application.fetch_env!(:alma, :media_root)
end
