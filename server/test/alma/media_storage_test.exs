defmodule Alma.Media.StorageTest do
  use ExUnit.Case, async: true

  alias Alma.Media.Storage

  test "a stored path becomes a URL under the public prefix" do
    prefix = Application.fetch_env!(:alma, :media_public_prefix)
    rel = "couple-123/2026/08/9f1c.jpg"

    assert Storage.url_for(rel) == "#{prefix}/#{rel}"
  end

  # `Alma.Media.delete_urls/1` and the janitor both turn a URL back into the
  # relative path by stripping this prefix, so the two have to agree.
  test "the URL a file gets is reversible back to its path" do
    prefix = Application.fetch_env!(:alma, :media_public_prefix)
    rel = "u_507f1f77bcf86cd799439011/2026/01/abc.mp4"

    assert String.replace_prefix(Storage.url_for(rel), prefix <> "/", "") == rel
  end
end
