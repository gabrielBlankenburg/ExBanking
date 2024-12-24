defmodule ExBanking.Transactions.GatewayClient do
  @moduledoc """
  API Client for the `ExBanking.Transactions.GatewayServer`
  """
  alias ExBanking.Transactions.GatewayServer

  defguard is_valid_input(sender, currency) when is_binary(sender) and is_binary(currency)

  defguard is_valid_input(sender, amount, currency)
           when is_binary(sender) and is_number(amount) and amount > 0 and is_binary(currency)

  defguard is_valid_input(sender, receiver, amount, currency)
           when is_binary(sender) and is_binary(receiver) and sender != receiver and
                  is_number(amount) and
                  amount > 0 and is_binary(currency)

  def start_link, do: GenServer.start_link(GatewayServer, nil, name: GatewayServer)

  def send_money(sender, receiver, amount, currency)
      when is_valid_input(sender, receiver, amount, currency),
      do:
        GenServer.call(GatewayServer, %{
          type: :send,
          sender: sender,
          receiver: receiver,
          currency: currency,
          amount: amount
        })

  def send_money(_sender, _receiver, _amount, _currency),
    do: {:error, :wrong_arguments}

  def deposit(sender, amount, currency) when is_valid_input(sender, amount, currency),
    do:
      GenServer.call(GatewayServer, %{
        type: :deposit,
        sender: sender,
        currency: currency,
        amount: amount
      })

  def deposit(_sender, _amount, _currency), do: {:error, :wrong_arguments}

  def withdraw(sender, amount, currency) when is_valid_input(sender, amount, currency),
    do:
      GenServer.call(GatewayServer, %{
        type: :withdraw,
        sender: sender,
        currency: currency,
        amount: amount
      })

  def withdraw(_sender, _amount, _currency), do: {:error, :wrong_arguments}

  def get_balance(username, currency) when is_valid_input(username, currency),
    do: GenServer.call(GatewayServer, %{type: :get_balance, sender: username, currency: currency})

  def get_balance(_username, _currency),
    do: {:error, :wrong_arguments}
end
