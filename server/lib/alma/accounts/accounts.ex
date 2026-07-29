defmodule Alma.Accounts do
  @moduledoc "User registration, login, and lookup. Mongo collection: `users`."

  alias Alma.MongoClient

  @coll "users"

  def register(email, password) when is_binary(email) and is_binary(password) do
    email = String.downcase(email)

    cond do
      not valid_email?(email) -> {:error, :invalid_email}
      String.length(password) < 8 -> {:error, :weak_password}
      get_user_by_email(email) != nil -> {:error, :email_taken}
      true ->
        doc = %{
          "email" => email,
          "password_hash" => Bcrypt.hash_pwd_salt(password),
          "avatar_url" => nil,
          "display_name" => nil,
          "couple_id" => nil,
          "current_status" => nil,
          "couple_started_at" => nil,
          "inserted_at" => DateTime.utc_now()
        }

        with {:ok, id} <- MongoClient.insert(@coll, doc) do
          {:ok, get_user(id)}
        end
    end
  end

  def authenticate(email, password) do
    email = String.downcase(email)

    case get_user_by_email(email) do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      user ->
        if Bcrypt.verify_pass(password, user["password_hash"]),
          do: {:ok, user},
          else: {:error, :invalid_credentials}
    end
  end

  def get_user(id), do: MongoClient.find_one(@coll, %{"_id" => id})
  def get_user_by_email(email), do: MongoClient.find_one(@coll, %{"email" => email})

  def update_user(id, set), do: MongoClient.update(@coll, %{"_id" => id}, set)

  def to_public(user) do
    user
    |> Map.take([
      "_id",
      "email",
      "avatar_url",
      "display_name",
      "couple_id",
      "current_status",
      "couple_started_at"
    ])
    |> Map.put("id", user["_id"])
  end

  defp valid_email?(s), do: Regex.match?(~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/, s)
end
