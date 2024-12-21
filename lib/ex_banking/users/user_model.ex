defmodule ExBanking.Users.UserModel do
  @moduledoc """
  Adapter for `ExBanking.Users.UsersTable`
  """
  alias ExBanking.Users.UsersTable

  @spec create_user(any()) :: :ok | {:error, :user_already_exists | :wrong_arguments}
  def create_user(username) when is_binary(username) do
    case UsersTable.create_user(username) do
      :ok -> :ok
      {:error, :user_already_exists} -> {:error, :user_already_exists}
    end
  end

  def create_user(_username), do: {:error, :wrong_arguments}

  def get_user(username) when is_binary(username) do
    case UsersTable.get_user(username) do
      {:ok, user} ->
        {:ok, user}

      {:error, :not_found} ->
        {:error, :user_does_not_exist}
    end
  end

  def get_user(_username), do: {:error, :wrong_arguments}

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

  @spec update_user(username :: String.t(), currencies :: map()) ::
          :ok | {:error, :user_does_not_exist}
  def update_user(username, currencies) when is_binary(username) and is_map(currencies) do
    case UsersTable.update_user(username, currencies) do
      {:error, :not_found} -> {:error, :user_does_not_exist}
      :ok -> :ok
    end
  end

  def update_user(_username, _currencies), do: {:error, :wrong_arguments}
end
