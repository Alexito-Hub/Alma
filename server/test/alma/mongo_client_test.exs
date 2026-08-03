defmodule Alma.MongoClientTest do
  use ExUnit.Case, async: true

  alias Alma.MongoClient

  describe "object_id/1" do
    test "decodes a 24-char hex id" do
      assert {:ok, %BSON.ObjectId{}} = MongoClient.object_id("507f1f77bcf86cd799439011")
    end

    test "passes an already-decoded id through" do
      {:ok, oid} = MongoClient.object_id("507f1f77bcf86cd799439011")
      assert {:ok, ^oid} = MongoClient.object_id(oid)
    end

    # Every one of these used to raise out of the context and surface as a 500
    # — with a stack trace attached, on a server that was running in dev mode.
    test "refuses anything that isn't one, instead of raising" do
      assert :error == MongoClient.object_id("not-an-id")
      assert :error == MongoClient.object_id("")
      assert :error == MongoClient.object_id("507f1f77bcf86cd79943901")
      assert :error == MongoClient.object_id("zzzzzzzzzzzzzzzzzzzzzzzz")
      assert :error == MongoClient.object_id(nil)
      assert :error == MongoClient.object_id(42)
      assert :error == MongoClient.object_id(%{})
    end

    test "round-trips through encode" do
      hex = "507f1f77bcf86cd799439011"
      {:ok, oid} = MongoClient.object_id(hex)
      assert BSON.ObjectId.encode!(oid) == hex
    end
  end
end
