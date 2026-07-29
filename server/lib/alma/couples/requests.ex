defmodule Alma.Couples.Requests do
  @moduledoc """
  Couple invitation flow. One user fills the proposed relationship metadata
  (when did we start, optional message) and sends it to a partner identified
  by the 8-char code (first 8 chars of their user id, lowercased).

  Stored in the `couple_requests` collection. Status transitions:
    pending -> accepted | rejected | cancelled

  Accepting wires both users under a fresh `couple_id` and uses the
  proposed `started_at` so the days-counter on both phones agrees.
  """

  alias Alma.Accounts
  alias Alma.Couples
  alias Alma.MongoClient

  @coll "couple_requests"
  @code_len 8

  def code_for(user), do: user["_id"] |> String.slice(0, @code_len) |> String.downcase()

  @doc """
  Build a new pending request from `from_user` toward whoever owns `to_code`.
  Returns {:ok, request_doc} | {:error, reason}.

  `attrs` may include:
    - "started_at"  : ISO-8601 string or DateTime (defaults to today UTC)
    - "message"     : free-form note shown to the recipient
  """
  def create(from_user, to_code, attrs \\ %{}) do
    code = normalize_code(to_code)

    with :ok <- ensure_not_linked(from_user),
         :ok <- ensure_valid_code(code),
         {:ok, recipient} <- find_recipient(from_user, code),
         :ok <- ensure_no_existing_pair(from_user, recipient) do
      started_at = parse_started_at(attrs["started_at"]) || DateTime.utc_now()
      message = attrs["message"] |> to_string() |> String.trim()

      doc = %{
        "from_user_id" => from_user["_id"],
        "from_email" => from_user["email"],
        "to_user_id" => recipient["_id"],
        "to_email" => recipient["email"],
        "to_code" => code,
        "proposed_started_at" => started_at,
        "message" => if(message == "", do: nil, else: message),
        "status" => "pending",
        "created_at" => DateTime.utc_now()
      }

      with {:ok, id} <- MongoClient.insert(@coll, doc) do
        request = Map.put(doc, "_id", id)
        notify(recipient["_id"], "couple_request:new", to_public(request))
        {:ok, request}
      end
    end
  end

  @doc "All pending requests where `user` is the recipient."
  def list_received(user) do
    MongoClient.find(@coll, %{"to_user_id" => user["_id"], "status" => "pending"})
    |> Enum.sort_by(& &1["created_at"], {:desc, DateTime})
    |> Enum.map(&to_public/1)
  end

  @doc "All requests where `user` is the sender, latest first."
  def list_sent(user) do
    MongoClient.find(@coll, %{"from_user_id" => user["_id"]})
    |> Enum.sort_by(& &1["created_at"], {:desc, DateTime})
    |> Enum.map(&to_public/1)
  end

  @doc """
  Recipient accepts a pending request. Links both users, deletes other
  pending requests for either party so the inboxes stay tidy.
  """
  def accept(user, request_id) do
    with {:ok, req} <- fetch_pending_for(user, :recipient, request_id),
         from_user when not is_nil(from_user) <- Accounts.get_user(req["from_user_id"]),
         :ok <- ensure_not_linked(user),
         :ok <- ensure_not_linked(from_user) do
      {:ok, updated_recipient} =
        Couples.bond(from_user, user, req["proposed_started_at"])

      mark_request(request_id, "accepted")
      cleanup_other_pending(user, from_user)
      notify(from_user["_id"], "couple_request:accepted", to_public(req))
      {:ok, updated_recipient}
    else
      nil -> {:error, :partner_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  def reject(user, request_id) do
    with {:ok, req} <- fetch_pending_for(user, :recipient, request_id) do
      mark_request(request_id, "rejected")
      notify(req["from_user_id"], "couple_request:rejected", %{"_id" => request_id})
      :ok
    end
  end

  def cancel(user, request_id) do
    with {:ok, _req} <- fetch_pending_for(user, :sender, request_id) do
      mark_request(request_id, "cancelled")
      :ok
    end
  end

  # --- helpers --------------------------------------------------------------

  defp normalize_code(code) when is_binary(code),
    do: code |> String.trim() |> String.downcase()

  defp normalize_code(_), do: ""

  defp ensure_not_linked(user) do
    if user["couple_id"] in [nil, ""], do: :ok, else: {:error, :already_linked}
  end

  defp ensure_valid_code(code) when byte_size(code) >= @code_len, do: :ok
  defp ensure_valid_code(_), do: {:error, :invalid_code}

  defp find_recipient(from_user, code) do
    # Scan unlinked users, prefix-match on lowercased id. We keep the list
    # small in practice (couples app), so the full scan is acceptable.
    recipient =
      MongoClient.find("users", %{"couple_id" => nil}, limit: 200)
      |> Enum.find(fn u ->
        u["_id"] != from_user["_id"] and
          String.starts_with?(String.downcase(u["_id"]), code)
      end)

    case recipient do
      nil -> {:error, :recipient_not_found}
      user -> {:ok, user}
    end
  end

  defp ensure_no_existing_pair(from_user, recipient) do
    case MongoClient.find(@coll, %{
           "status" => "pending",
           "from_user_id" => from_user["_id"],
           "to_user_id" => recipient["_id"]
         }) do
      [] -> :ok
      _ -> {:error, :request_already_sent}
    end
  end

  defp fetch_pending_for(user, role, request_id) do
    case MongoClient.find_one(@coll, %{"_id" => request_id}) do
      nil ->
        {:error, :not_found}

      %{"status" => "pending"} = req ->
        owner_id =
          case role do
            :recipient -> req["to_user_id"]
            :sender -> req["from_user_id"]
          end

        if owner_id == user["_id"], do: {:ok, req}, else: {:error, :forbidden}

      _ ->
        {:error, :already_resolved}
    end
  end

  defp mark_request(request_id, status) do
    MongoClient.update(@coll, %{"_id" => request_id}, %{
      "status" => status,
      "responded_at" => DateTime.utc_now()
    })
  end

  defp cleanup_other_pending(user_a, user_b) do
    # Any other pending requests touching either user become stale once
    # they're bonded — mark them cancelled so the inboxes clear out.
    ids = [user_a["_id"], user_b["_id"]]

    Enum.each(
      MongoClient.find(@coll, %{"status" => "pending"}),
      fn req ->
        if req["from_user_id"] in ids or req["to_user_id"] in ids do
          mark_request(req["_id"], "cancelled")
        end
      end
    )
  end

  defp parse_started_at(nil), do: nil
  defp parse_started_at(%DateTime{} = dt), do: dt

  defp parse_started_at(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_started_at(_), do: nil

  defp notify(user_id, event, payload) do
    Phoenix.PubSub.broadcast(
      Alma.PubSub,
      "user:#{user_id}",
      {String.to_atom(event), payload}
    )
  end

  def to_public(req) do
    %{
      "id" => req["_id"],
      "from_user_id" => req["from_user_id"],
      "from_email" => req["from_email"],
      "to_user_id" => req["to_user_id"],
      "to_email" => req["to_email"],
      "to_code" => req["to_code"],
      "proposed_started_at" => req["proposed_started_at"],
      "message" => req["message"],
      "status" => req["status"],
      "created_at" => req["created_at"],
      "responded_at" => req["responded_at"]
    }
  end
end
