defmodule ExBanking.Transactions.GatewayClient do
  @moduledoc """
  API Client for the `ExBanking.Transactions.GatewayServer`
  """
  alias ExBanking.Transactions.GatewayServer

  alias ExBanking.Common.Money

  defguard is_valid_input(sender, currency) when is_binary(sender) and is_binary(currency)

  defguard is_valid_input(sender, amount, currency)
           when is_binary(sender) and is_number(amount) and amount > 0 and is_binary(currency)

  defguard is_valid_input(sender, receiver, amount, currency)
           when is_binary(sender) and is_binary(receiver) and sender != receiver and
                  is_number(amount) and
                  amount > 0 and is_binary(currency)

  @spec start_link() :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link, do: GenServer.start_link(GatewayServer, nil, name: GatewayServer)

  @doc """
  Transfer money from sender to receiver for the given currency
  """
  @spec send_money(binary(), binary(), number(), binary()) ::
          {:ok, from_user_balance :: number, to_user_balance :: number}
          | {:error,
             :wrong_arguments
             | :not_enough_money
             | :sender_does_not_exist
             | :receiver_does_not_exist
             | :too_many_requests_to_sender
             | :too_many_requests_to_receiver}
  def send_money(sender, receiver, amount, currency)
      when is_valid_input(sender, receiver, amount, currency),
      do:
        do_call(%{
          type: :send,
          sender: sender,
          receiver: receiver,
          currency: currency,
          amount: amount
        })

  def send_money(_sender, _receiver, _amount, _currency),
    do: {:error, :wrong_arguments}

  @doc """
  Deposits money for sender in the given currency
  """
  @spec deposit(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number}
          | {:error, :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user}
  def deposit(sender, amount, currency) when is_valid_input(sender, amount, currency),
    do:
      do_call(%{
        type: :deposit,
        sender: sender,
        currency: currency,
        amount: amount
      })

  def deposit(_sender, _amount, _currency), do: {:error, :wrong_arguments}

  @doc """
  sender withdraws money in the given currency
  """
  @spec withdraw(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number}
          | {:error,
             :wrong_arguments
             | :user_does_not_exist
             | :not_enough_money
             | :too_many_requests_to_user}
  def withdraw(sender, amount, currency) when is_valid_input(sender, amount, currency),
    do:
      do_call(%{
        type: :withdraw,
        sender: sender,
        currency: currency,
        amount: amount
      })

  def withdraw(_sender, _amount, _currency), do: {:error, :wrong_arguments}

  @doc """
  Get balance for user in the given currency
  """
  @spec get_balance(user :: String.t(), currency :: String.t()) ::
          {:ok, balance :: number}
          | {:error, :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user}
  def get_balance(username, currency) when is_valid_input(username, currency) do
    case GenServer.call(GatewayServer, %{type: :get_balance, sender: username, currency: currency}) do
      {:ok, balance} -> {:ok, Money.to_float!(balance)}
      error -> error
    end
  end

  def get_balance(_username, _currency),
    do: {:error, :wrong_arguments}

  defp do_call(args) do
    case Money.parse(args.amount) do
      {:ok, amount} ->
        args
        |> Map.put(:amount, amount)
        |> then(&GenServer.call(GatewayServer, &1))
        |> handle_response()

      :error ->
        {:error, :wrong_arguments}
    end
  end

  defp handle_response({:ok, balance}), do: {:ok, Money.to_float!(balance)}

  defp handle_response({:ok, sender_balance, receiver_balance}),
    do: {:ok, Money.to_float!(sender_balance), Money.to_float!(receiver_balance)}

  defp handle_response(response), do: response
end
