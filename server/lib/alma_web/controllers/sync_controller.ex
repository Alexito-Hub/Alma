defmodule AlmaWeb.SyncController do
  @moduledoc """
  Batch endpoint used by the Flutter WorkManager isolate. Accepts a payload
  with arrays per collection. Echoes back per-item ack with {client_id, id}
  so the client can flip its local `sync_status` to `synced`.
  """
  use Phoenix.Controller, formats: [:json]

  alias Alma.Notes

  def batch(conn, params) do
    user = conn.assigns.current_user

    notes_ack =
      (params["notes"] || [])
      |> Enum.map(fn note ->
        case Notes.create(user, note["body"], note["created_at"]) do
          {:ok, doc} -> %{"client_id" => note["client_id"], "id" => doc["_id"]}
          _ -> %{"client_id" => note["client_id"], "error" => "failed"}
        end
      end)

    json(conn, %{notes: notes_ack})
  end
end
