defmodule Alma.MongoClient do
  @moduledoc """
  Thin facade over the named `:mongo` process started by `Alma.Application`.
  Centralizes BSON id conversion and lets contexts speak in plain maps.
  """

  alias BSON.ObjectId

  @spec insert(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def insert(coll, doc) do
    case Mongo.insert_one(:mongo, coll, doc) do
      {:ok, %Mongo.InsertOneResult{inserted_id: id}} -> {:ok, ObjectId.encode!(id)}
      {:error, err} -> {:error, err}
    end
  end

  @spec find_one(String.t(), map()) :: map() | nil
  def find_one(coll, filter) do
    Mongo.find_one(:mongo, coll, normalize_filter(filter))
    |> stringify_id()
  end

  @spec find(String.t(), map(), keyword()) :: [map()]
  def find(coll, filter \\ %{}, opts \\ []) do
    Mongo.find(:mongo, coll, normalize_filter(filter), opts)
    |> Enum.map(&stringify_id/1)
  end

  @spec update(String.t(), map(), map()) :: :ok | {:error, term()}
  def update(coll, filter, set_doc) do
    case Mongo.update_one(:mongo, coll, normalize_filter(filter),
           %{"$set" => set_doc},
           upsert: true
         ) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, err}
    end
  end

  defp normalize_filter(%{"_id" => id} = f) when is_binary(id) do
    %{f | "_id" => ObjectId.decode!(id)}
  end

  defp normalize_filter(f), do: f

  defp stringify_id(nil), do: nil

  defp stringify_id(%{"_id" => %BSON.ObjectId{} = id} = doc) do
    Map.put(doc, "_id", ObjectId.encode!(id))
  end

  defp stringify_id(doc), do: doc
end
