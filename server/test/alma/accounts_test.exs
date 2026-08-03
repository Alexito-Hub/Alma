defmodule Alma.AccountsTest do
  @moduledoc """
  Registration gating. Deliberately not touching Mongo — these are the rules
  that decide whether a stranger reaching the tunnel gets an account at all.
  """
  use ExUnit.Case, async: false

  alias Alma.Accounts

  setup do
    original = System.get_env("ALMA_ALLOWED_EMAILS")

    on_exit(fn ->
      if original, do: System.put_env("ALMA_ALLOWED_EMAILS", original)
      if is_nil(original), do: System.delete_env("ALMA_ALLOWED_EMAILS")
    end)

    :ok
  end

  test "unset allowlist leaves registration open" do
    System.delete_env("ALMA_ALLOWED_EMAILS")
    assert Accounts.allowed?("anyone@example.com")
  end

  test "an empty allowlist counts as unset, not as 'nobody'" do
    System.put_env("ALMA_ALLOWED_EMAILS", "   ,  ,")
    assert Accounts.allowed?("anyone@example.com")
  end

  test "only listed addresses may register" do
    System.put_env("ALMA_ALLOWED_EMAILS", "ale@example.com,may@example.com")

    assert Accounts.allowed?("ale@example.com")
    assert Accounts.allowed?("may@example.com")
    refute Accounts.allowed?("stranger@example.com")
  end

  test "matching ignores case and surrounding spaces" do
    System.put_env("ALMA_ALLOWED_EMAILS", " Ale@Example.com , may@example.com ")

    assert Accounts.allowed?("ALE@EXAMPLE.COM")
    assert Accounts.allowed?("ale@example.com")
  end

  test "registering an address off the list is refused before anything is written" do
    System.put_env("ALMA_ALLOWED_EMAILS", "ale@example.com")

    assert {:error, :registration_closed} =
             Accounts.register("stranger@example.com", "a-long-enough-password")
  end

  test "a malformed address is rejected ahead of the allowlist" do
    System.put_env("ALMA_ALLOWED_EMAILS", "ale@example.com")
    assert {:error, :invalid_email} = Accounts.register("nope", "a-long-enough-password")
  end
end
