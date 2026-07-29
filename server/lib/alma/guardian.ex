defmodule Alma.Guardian do
  use Guardian, otp_app: :alma

  alias Alma.Accounts

  def subject_for_token(%{"_id" => id}, _claims), do: {:ok, id}
  def subject_for_token(_, _), do: {:error, :unknown_resource}

  def resource_from_claims(%{"sub" => id}) do
    case Accounts.get_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
