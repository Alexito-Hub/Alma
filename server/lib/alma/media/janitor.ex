defmodule Alma.MediaJanitor do
  @moduledoc """
  Periodically clears media files that nothing references any more.

  Deletion at the source (a post or note removed, a status photo replaced) is
  handled by `Alma.Media`; this is the safety net for whatever slips through —
  an upload whose post never got created, a crash between the two steps.

  Conservative on purpose: only files older than a week are considered. The
  client uploads media first and creates the document afterwards, so a file can
  legitimately sit unreferenced while a post retries — a week is far longer
  than any such gap, and orphans older than that are certainly rubbish.
  """
  use GenServer

  require Logger

  @first_run :timer.minutes(5)
  @interval :timer.hours(6)
  @min_age_seconds 7 * 86_400

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc "Run a sweep immediately. Returns `{deleted_count, freed_bytes}`."
  def sweep_now, do: GenServer.call(__MODULE__, :sweep, 120_000)

  @impl true
  def init(_) do
    Process.send_after(self(), :sweep, @first_run)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    run()
    Process.send_after(self(), :sweep, @interval)
    {:noreply, state}
  end

  @impl true
  def handle_call(:sweep, _from, state), do: {:reply, run(), state}

  defp run do
    Alma.Media.sweep_orphans(@min_age_seconds)
  rescue
    e ->
      Logger.warning("media janitor failed: #{Exception.message(e)}")
      {0, 0}
  catch
    :exit, reason ->
      Logger.warning("media janitor exited: #{inspect(reason)}")
      {0, 0}
  end
end
