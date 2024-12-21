defmodule ExBanking do
  @moduledoc """
  API for banking operations
  """
  alias ExBanking.Users.UserModel
  alias ExBanking.Transactions.Gateway

  @doc """
  Creates a user in the system
  """
  @spec create_user(user :: String.t()) :: :ok | {:error, :wrong_arguments | :user_already_exists}
  def create_user(user), do: UserModel.create_user(user)

  @spec deposit(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number}
          | {:error, :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user}
  def deposit(user, amount, currency), do: Gateway.deposit(user, amount, currency)

  @doc """
  User withdraw money for the given currency and amount
  """
  @spec withdraw(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number}
          | {:error,
             :wrong_arguments
             | :user_does_not_exist
             | :not_enough_money
             | :too_many_requests_to_user}
  def withdraw(user, amount, currency), do: Gateway.withdraw(user, amount, currency)

  @doc """
  Gets the user's balance of given currency
  """
  @spec get_balance(user :: String.t(), currency :: String.t()) ::
          {:ok, balance :: number}
          | {:error, :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user}
  def get_balance(user, currency), do: Gateway.get_balance(user, currency)

  @doc """
  Transfer money from sender to receiver
  """
  @spec send(
          from_user :: String.t(),
          to_user :: String.t(),
          amount :: number,
          currency :: String.t()
        ) ::
          {:ok, from_user_balance :: number, to_user_balance :: number}
          | {:error,
             :wrong_arguments
             | :not_enough_money
             | :sender_does_not_exist
             | :receiver_does_not_exist
             | :too_many_requests_to_sender
             | :too_many_requests_to_receiver}
  def send(from_user, to_user, amount, currency),
    do: Gateway.send_money(from_user, to_user, amount, currency)
end
