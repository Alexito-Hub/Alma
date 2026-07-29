defmodule Alma.Couples do
  @moduledoc """
  Couple linking — pairs two users under a shared `couple_id` so all their
  posts/notes/status are partitioned by that id.

  The new primary path is via `Alma.Couples.Requests` (one user sends an
  invitation, the other accepts). `link/2` is kept for backward compat with
  the old single-step code flow.
  """

  alias Alma.Accounts
  alias Alma.MongoClient

  @coll "couple_settings"

  @doc """
  Legacy single-step linker. Used when one user knows the partner's 8-char
  code and they share a `started_at` baseline of "now". Prefer the request
  flow (`Alma.Couples.Requests.create/3` + `accept/2`) for new clients.
  """
  def link(current_user, code) when is_binary(code) do
    code = code |> String.trim() |> String.downcase()

    cond do
      current_user["couple_id"] not in [nil, ""] ->
        {:error, :already_linked}

      String.length(code) < 8 ->
        {:error, :invalid_code}

      true ->
        partner =
          MongoClient.find("users", %{"couple_id" => nil}, limit: 200)
          |> Enum.find(fn u ->
            u["_id"] != current_user["_id"] and
              String.starts_with?(String.downcase(u["_id"]), code)
          end)

        case partner do
          nil -> {:error, :not_found}
          partner -> bond(current_user, partner, DateTime.utc_now())
        end
    end
  end

  @doc """
  Bond two users under a fresh couple_id with the given started_at.
  Returns {:ok, refreshed_user_a}.
  """
  def bond(user_a, user_b, started_at) do
    couple_id = UUID.uuid4()
    started_at = normalize_started_at(started_at)

    Accounts.update_user(user_a["_id"], %{
      "couple_id" => couple_id,
      "couple_started_at" => started_at
    })

    Accounts.update_user(user_b["_id"], %{
      "couple_id" => couple_id,
      "couple_started_at" => started_at
    })

    MongoClient.update(
      @coll,
      %{"couple_id" => couple_id},
      %{
        "couple_id" => couple_id,
        "member_ids" => [user_a["_id"], user_b["_id"]],
        "background_url" => nil,
        "started_at" => started_at,
        "created_at" => DateTime.utc_now()
      }
    )

    notify_user(user_a["_id"], "couple_bonded", %{
      "couple_id" => couple_id,
      "partner_id" => user_b["_id"]
    })

    notify_user(user_b["_id"], "couple_bonded", %{
      "couple_id" => couple_id,
      "partner_id" => user_a["_id"]
    })

    {:ok, Accounts.get_user(user_a["_id"])}
  end

  defp normalize_started_at(%DateTime{} = dt), do: dt

  defp normalize_started_at(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp normalize_started_at(_), do: DateTime.utc_now()

  defp notify_user(user_id, event, payload) do
    Phoenix.PubSub.broadcast(
      Alma.PubSub,
      "user:#{user_id}",
      {String.to_atom(event), payload}
    )
  end
end
