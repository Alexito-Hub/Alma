defmodule AlmaWeb.UserSocket do
  use Phoenix.Socket

  channel "couple:*", AlmaWeb.CoupleChannel
  channel "post:*", AlmaWeb.PostChannel
  channel "user:*", AlmaWeb.UserChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Alma.Guardian.resource_from_token(token) do
      {:ok, user, _claims} -> {:ok, assign(socket, :current_user, user)}
      _ -> :error
    end
  end

  def connect(_, _, _), do: :error

  @impl true
  def id(socket), do: "users_socket:#{socket.assigns.current_user["_id"]}"
end
