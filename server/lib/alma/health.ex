defmodule Alma.Health do
  @moduledoc """
  Aggregated server health, built for eyeballing from a phone as much as for
  uptime monitors.

  Four independent checks — Mongo, media storage, disk, and the BEAM itself —
  each reporting `ok` / `warn` / `error` plus the numbers behind the verdict.
  A failure of a *critical* check (Mongo) makes the whole report `error`; a
  non-critical warning makes it `degraded`. Every check is wrapped so a broken
  probe degrades the report instead of crashing the request.

  `report(include_data: true)` adds database statistics and per-collection
  document counts. Those stay out of the public payload — they describe the
  couple's data volume, so the detailed variant sits behind auth.
  """

  # Collections mirrored from the context modules (Accounts, Couples, Notes…).
  @collections ~w(users couple_settings couple_requests notes posts comments special_dates media)

  @doc """
  Build the health report. Pass `include_data: true` for database statistics
  and collection counts.
  """
  def report(opts \\ []) do
    include_data = Keyword.get(opts, :include_data, false)
    uptime = uptime_seconds()

    checks = %{
      "mongo" => mongo_check(include_data),
      "media" => media_check(),
      "disk" => disk_check(),
      "system" => system_check()
    }

    %{
      "status" => overall_status(checks),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "uptime_seconds" => uptime,
      "uptime_human" => human_duration(uptime),
      "version" => version(),
      "environment" => environment(),
      "checks" => checks
    }
  end

  @doc "HTTP status to answer a report with: 503 only when something critical is down."
  def http_status(%{"status" => "error"}), do: 503
  def http_status(_), do: 200

  # ── aggregation ────────────────────────────────────────────────────────────

  # Mongo is the only check the API cannot work without; the rest degrade.
  defp overall_status(checks) do
    cond do
      status_of(checks, "mongo") == "error" -> "error"
      Enum.any?(checks, fn {_name, c} -> c["status"] in ["warn", "error"] end) -> "degraded"
      true -> "ok"
    end
  end

  defp status_of(checks, name), do: get_in(checks, [name, "status"])

  # ── mongo ──────────────────────────────────────────────────────────────────

  defp mongo_check(include_data) do
    {micros, result} = :timer.tc(fn -> Mongo.command(:mongo, [ping: 1], []) end)
    latency = Float.round(micros / 1000, 1)

    case result do
      {:ok, _} ->
        %{"status" => "ok", "latency_ms" => latency, "pool_size" => pool_size()}
        |> maybe_merge(include_data, &db_stats/0)
        |> maybe_merge(include_data, &collection_counts/0)

      {:error, err} ->
        %{"status" => "error", "latency_ms" => latency, "error" => describe(err)}
    end
  rescue
    e -> %{"status" => "error", "error" => Exception.message(e)}
  catch
    :exit, reason -> %{"status" => "error", "error" => describe(reason)}
  end

  defp maybe_merge(map, false, _fun), do: map
  defp maybe_merge(map, true, fun), do: Map.merge(map, fun.())

  defp db_stats do
    case Mongo.command(:mongo, [dbStats: 1], []) do
      {:ok, s} ->
        %{
          "database" => s["db"],
          "collections" => s["collections"],
          "documents" => as_int(s["objects"]),
          "data_size_bytes" => as_int(s["dataSize"]),
          "data_size_human" => human_bytes(as_int(s["dataSize"])),
          "storage_size_bytes" => as_int(s["storageSize"]),
          "index_size_bytes" => as_int(s["indexSize"])
        }

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  catch
    :exit, _ -> %{}
  end

  defp collection_counts do
    counts =
      Map.new(@collections, fn coll ->
        {coll, count_documents(coll)}
      end)

    %{"counts" => counts}
  end

  defp count_documents(coll) do
    case Mongo.count_documents(:mongo, coll, %{}) do
      {:ok, n} -> n
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp pool_size do
    Application.get_env(:alma, :mongo, [])[:pool_size]
  end

  # ── media storage ──────────────────────────────────────────────────────────

  defp media_check do
    root = media_root()

    case File.stat(root) do
      {:ok, %File.Stat{access: access}} ->
        writable = access in [:write, :read_write]
        {files, bytes} = media_usage(root)

        %{
          "status" => if(writable, do: "ok", else: "warn"),
          "root" => root,
          "writable" => writable,
          "files" => files,
          "size_bytes" => bytes,
          "size_human" => human_bytes(bytes)
        }

      {:error, reason} ->
        # Missing root is only a warning: it is created on the first upload.
        %{
          "status" => "warn",
          "root" => root,
          "writable" => false,
          "error" => to_string(reason)
        }
    end
  rescue
    e -> %{"status" => "warn", "error" => Exception.message(e)}
  end

  # Walks the media tree once, summing regular files. Fine for a couple's
  # library; revisit if this ever holds tens of thousands of files.
  defp media_usage(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.reduce({0, 0}, fn path, {count, bytes} = acc ->
      case File.stat(path) do
        {:ok, %File.Stat{type: :regular, size: size}} -> {count + 1, bytes + size}
        _ -> acc
      end
    end)
  end

  defp media_root do
    :alma |> Application.fetch_env!(:media_root) |> Path.expand()
  end

  # ── disk ───────────────────────────────────────────────────────────────────

  # `df` keeps this dependency-free (no :os_mon in the supervision tree).
  defp disk_check do
    case System.cmd("df", ["-Pk", media_root()], stderr_to_stdout: true) do
      {output, 0} ->
        output |> String.split("\n") |> Enum.at(1) |> parse_df()

      _ ->
        %{"status" => "unknown"}
    end
  rescue
    _ -> %{"status" => "unknown"}
  end

  defp parse_df(nil), do: %{"status" => "unknown"}

  defp parse_df(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [_fs, total, used, avail, _capacity, mount | _] ->
        total_b = kb_to_bytes(total)
        used_b = kb_to_bytes(used)
        free_b = kb_to_bytes(avail)
        percent = if total_b > 0, do: Float.round(used_b / total_b * 100, 1), else: 0.0

        %{
          "status" => if(percent >= 90, do: "warn", else: "ok"),
          "mount" => mount,
          "total_bytes" => total_b,
          "total_human" => human_bytes(total_b),
          "used_bytes" => used_b,
          "free_bytes" => free_b,
          "free_human" => human_bytes(free_b),
          "used_percent" => percent
        }

      _ ->
        %{"status" => "unknown"}
    end
  end

  defp kb_to_bytes(kb), do: String.to_integer(kb) * 1024

  # ── BEAM / system ──────────────────────────────────────────────────────────

  defp system_check do
    processes = :erlang.system_info(:process_count)
    limit = :erlang.system_info(:process_limit)

    %{
      "status" => if(processes / limit > 0.8, do: "warn", else: "ok"),
      "memory_bytes" => :erlang.memory(:total),
      "memory_human" => human_bytes(:erlang.memory(:total)),
      "processes" => processes,
      "process_limit" => limit,
      "schedulers" => :erlang.system_info(:schedulers_online),
      "elixir" => System.version(),
      "otp" => System.otp_release()
    }
  end

  # ── misc ───────────────────────────────────────────────────────────────────

  defp uptime_seconds do
    {wall_clock_ms, _since_last_call} = :erlang.statistics(:wall_clock)
    div(wall_clock_ms, 1000)
  end

  defp version do
    case Application.spec(:alma, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end

  defp environment do
    :alma |> Application.get_env(:env, :unknown) |> to_string()
  end

  defp as_int(nil), do: nil
  defp as_int(n) when is_integer(n), do: n
  defp as_int(n) when is_float(n), do: round(n)
  defp as_int(_), do: nil

  defp describe(term) when is_binary(term), do: term
  defp describe(term), do: inspect(term)

  defp human_bytes(nil), do: nil
  defp human_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  defp human_bytes(bytes) do
    {value, unit} =
      cond do
        bytes >= 1024 ** 4 -> {bytes / 1024 ** 4, "TB"}
        bytes >= 1024 ** 3 -> {bytes / 1024 ** 3, "GB"}
        bytes >= 1024 ** 2 -> {bytes / 1024 ** 2, "MB"}
        true -> {bytes / 1024, "KB"}
      end

    "#{Float.round(value, 1)} #{unit}"
  end

  defp human_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp human_duration(seconds) do
    days = div(seconds, 86_400)
    hours = seconds |> rem(86_400) |> div(3600)
    minutes = seconds |> rem(3600) |> div(60)

    [{days, "d"}, {hours, "h"}, {minutes, "m"}]
    |> Enum.filter(fn {value, _unit} -> value > 0 end)
    |> Enum.map_join(" ", fn {value, unit} -> "#{value}#{unit}" end)
  end
end
