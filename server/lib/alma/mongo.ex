defmodule Alma.MongoClient do
  @moduledoc """
  Thin facade over the named `:mongo` process started by `Alma.Application`.
  Centralizes BSON id conversion and lets contexts speak in plain maps.
  """

  alias BSON.ObjectId

  @doc """
  Decode a hex string into a BSON ObjectId, without raising.

  Every context needs this, and every one of them used to call
  `BSON.ObjectId.decode!/1` directly — which blows up on anything that isn't
  24 hex characters. A malformed id in a URL therefore became a 500 (with a
  stack trace attached, in a dev-mode container) where a 404 was the honest
  answer. Decoding lives here so no caller has to remember.
  """
  @spec object_id(term()) :: {:ok, ObjectId.t()} | :error
  def object_id(%ObjectId{} = oid), do: {:ok, oid}

  def object_id(id) when is_binary(id) do
    {:ok, ObjectId.decode!(id)}
  rescue
    _ -> :error
  end

  def object_id(_), do: :error

  @spec insert(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def insert(coll, doc) do
    case Mongo.insert_one(:mongo, coll, doc) do
      {:ok, %Mongo.InsertOneResult{inserted_id: id}} -> {:ok, ObjectId.encode!(id)}
      {:error, err} -> {:error, err}
    end
  end

  @spec find_one(String.t(), map()) :: map() | nil
  def find_one(coll, filter) do
    case normalize_filter(filter) do
      :error ->
        nil

      f ->
        Mongo.find_one(:mongo, coll, f)
        |> stringify_id()
    end
  end

  @spec find(String.t(), map(), keyword()) :: [map()]
  def find(coll, filter \\ %{}, opts \\ []) do
    case normalize_filter(filter) do
      :error ->
        []

      f ->
        Mongo.find(:mongo, coll, f, opts)
        |> Enum.map(&stringify_id/1)
    end
  end

  @spec update(String.t(), map(), map()) :: :ok | {:error, term()}
  def update(coll, filter, set_doc) do
    case normalize_filter(filter) do
      :error ->
        {:error, :invalid_id}

      f ->
        case Mongo.update_one(:mongo, coll, f, %{"$set" => set_doc}, upsert: true) do
          {:ok, _} -> :ok
          {:error, err} -> {:error, err}
        end
    end
  end

  # An unparseable `_id` isn't a database error, it's "no such document" —
  # so it short-circuits to nil/[] rather than raising out of the caller.
  defp normalize_filter(%{"_id" => id} = f) when is_binary(id) do
    case object_id(id) do
      {:ok, oid} -> %{f | "_id" => oid}
      :error -> :error
    end
  end

  defp normalize_filter(f), do: f

  defp stringify_id(nil), do: nil

  defp stringify_id(%{"_id" => %ObjectId{} = id} = doc) do
    Map.put(doc, "_id", ObjectId.encode!(id))
  end

  defp stringify_id(doc), do: doc
end
