defmodule AlmaWeb.Cors do
  @moduledoc """
  Which browser origins may call the API.

  Alma has no browser client — the Flutter app sends no `Origin` header, so
  CORS never applied to it — yet the API answered `*`, telling every site on
  the internet it was welcome to try. The allowlist is the tunnel host itself
  (so opening `/health` in a browser still works) plus anything named in
  `ALMA_CORS_ORIGINS`, comma-separated.

  Evaluated per request rather than baked in at compile time, because the host
  only becomes known at boot from `ALMA_HOST`.
  """

  def origins do
    extra() ++ host_origins()
  end

  defp extra do
    (System.get_env("ALMA_CORS_ORIGINS") || "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp host_origins do
    case AlmaWeb.Endpoint.config(:url)[:host] do
      host when is_binary(host) and host != "" ->
        ["https://#{host}", "http://#{host}", "https://#{host}:443"]

      _ ->
        []
    end
  end
end
