defmodule AlmaWeb.HealthController do
  @moduledoc """
  Health endpoints.

  * `GET /health` — public. Liveness plus operational state (Mongo reachability
    and latency, media storage, disk, BEAM). Answers 503 when a critical check
    fails, so uptime monitors and the Cloudflare tunnel see a real failure.
  * `GET /api/health` — authenticated. Everything above plus database
    statistics and per-collection counts, which describe the couple's data and
    therefore stay private.
  """
  use Phoenix.Controller, formats: [:json]

  alias Alma.Health

  def show(conn, _params), do: respond(conn, Health.report())

  def detailed(conn, _params), do: respond(conn, Health.report(include_data: true))

  defp respond(conn, report) do
    conn
    |> put_status(Health.http_status(report))
    |> json(report)
  end
end
