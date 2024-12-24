defmodule ExBanking.Users.UserAdapter do
  @moduledoc """
  Adapter for `ExBanking.Users.UsersTable`
  """
  alias ExBanking.Users.UsersTable

  defstruct [:id, :currencies]

  @doc """
  Create a new user without any currency stored
  """
  @spec create_user(binary()) :: :ok | {:error, :user_already_exists | :wrong_arguments}
  def create_user(username) when is_binary(username) do
    case UsersTable.create_user(username) do
      :ok -> :ok
      {:error, :user_already_exists} -> {:error, :user_already_exists}
    end
  end

  def create_user(_username), do: {:error, :wrong_arguments}

  @doc """
  Gets an user by id
  """
  @spec get_user(binary()) ::
          nil
          | %ExBanking.Users.UserAdapter{currencies: any(), id: any()}
  def get_user(username) when is_binary(username) do
    case UsersTable.get_user(username) do
      {:ok, user} ->
        parse_result(user)

      _ ->
        nil
    end
  end

  def get_user(_username), do: {:error, :wrong_arguments}

  @doc """
  Get user balance by given id
  """
  @spec get_balance(username :: String.t(), currency :: String.t()) ::
          {:ok, balance :: number}
          | {:error, :wrong_arguments | :user_does_not_exist}
  def get_balance(username, currency) when is_binary(username) and is_binary(currency) do
    case UsersTable.get_user(username) do
      {:ok, {_username, currencies}} ->
        {:ok, Map.get(currencies, currency, 0)}

      {:error, :not_found} ->
        {:error, :user_does_not_exist}
    end
  end

  def get_balance(_username, _currency), do: {:error, :wrong_arguments}

  @doc """
  Updates users currencies
  """
  @spec update_user(username :: String.t(), currencies :: map()) ::
          :ok | {:error, :user_does_not_exist}
  def update_user(username, currencies) when is_binary(username) and is_map(currencies) do
    case UsersTable.update_user(username, currencies) do
      {:error, :not_found} -> {:error, :user_does_not_exist}
      :ok -> :ok
    end
  end

  def update_user(_username, _currencies), do: {:error, :wrong_arguments}

  defp parse_result({username, currencies}), do: %__MODULE__{id: username, currencies: currencies}
end
