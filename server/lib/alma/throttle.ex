defmodule Alma.Throttle do
  @moduledoc """
  Counts failed attempts per key and locks a key out once there have been too
  many inside a window.

  In memory on purpose: a restart forgets everything. The goal is to make an
  online guessing run take longer than it is worth, not to keep an audit
  trail. The window is measured from the *last* failure, so someone who keeps
  hammering stays locked out rather than getting a fresh allowance every few
  minutes.

  Written for the couple PIN, where four digits are 10.000 combinations and
  the endpoint answered as fast as you could ask it.
  """
  use GenServer

  @table :alma_throttle
  @sweep_interval :timer.minutes(10)
  @forget_after_seconds 3_600

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  `:ok` when `key` may try again, `{:blocked, seconds_remaining}` when it has
  used up `max_attempts` inside `window_seconds`.
  """
  @spec check(term(), pos_integer(), non_neg_integer()) :: :ok | {:blocked, pos_integer()}
  def check(key, max_attempts, window_seconds) do
    case :ets.lookup(@table, key) do
      [{^key, count, last}] when count >= max_attempts ->
        remaining = window_seconds - (System.system_time(:second) - last)

        if remaining > 0 do
          {:blocked, remaining}
        else
          :ets.delete(@table, key)
          :ok
        end

      _ ->
        :ok
    end
  rescue
    # Never let the limiter itself deny service if the table isn't up yet.
    ArgumentError -> :ok
  end

  @doc "Record a failed attempt for `key`."
  def fail(key) do
    now = System.system_time(:second)
    # insert_new + update_counter so two concurrent requests can't lose a count.
    :ets.insert_new(@table, {key, 0, now})
    :ets.update_counter(@table, key, {2, 1})
    :ets.update_element(@table, key, {3, now})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Forget `key`'s failures — call after a success."
  def reset(key) do
    :ets.delete(@table, key)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = System.system_time(:second) - @forget_after_seconds
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)
end
