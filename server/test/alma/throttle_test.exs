defmodule Alma.ThrottleTest do
  @moduledoc """
  The limiter behind the couple PIN. Four digits is 10.000 combinations, so
  what matters here is that failures actually accumulate and that a success
  clears them.
  """
  use ExUnit.Case, async: false

  alias Alma.Throttle

  setup do
    key = {:test, System.unique_integer([:positive])}
    on_exit(fn -> Throttle.reset(key) end)
    {:ok, key: key}
  end

  test "a fresh key may try", %{key: key} do
    assert :ok == Throttle.check(key, 3, 60)
  end

  test "blocks once the attempts are used up", %{key: key} do
    Throttle.fail(key)
    Throttle.fail(key)
    assert :ok == Throttle.check(key, 3, 60)

    Throttle.fail(key)
    assert {:blocked, seconds} = Throttle.check(key, 3, 60)
    assert seconds > 0
    assert seconds <= 60
  end

  test "a success clears the count", %{key: key} do
    for _ <- 1..5, do: Throttle.fail(key)
    assert {:blocked, _} = Throttle.check(key, 3, 60)

    Throttle.reset(key)
    assert :ok == Throttle.check(key, 3, 60)
  end

  test "the block lifts once the window has passed", %{key: key} do
    for _ <- 1..3, do: Throttle.fail(key)
    # A window of zero seconds is one that already elapsed.
    assert :ok == Throttle.check(key, 3, 0)
  end

  test "keys don't interfere with each other", %{key: key} do
    other = {:test, System.unique_integer([:positive])}
    on_exit(fn -> Throttle.reset(other) end)

    for _ <- 1..3, do: Throttle.fail(key)

    assert {:blocked, _} = Throttle.check(key, 3, 60)
    assert :ok == Throttle.check(other, 3, 60)
  end
end
