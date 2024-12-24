defmodule ExBanking.Transactions.TransactionWorker do
  @moduledoc """
  Spawns a transaction, that will execute the operation.
  For each operation in a single transaction (eg. send does two ops, by removing the money from sender and adding to the receiver)
  the transaction will persist in its memory transaction table in the field `operations`.
  If the transaction fails in any step, it will look the operations and undo the transaction.
  Operations follow a pattern of {:credit | :debit, amount, currency, status, new_balance}
  The new balance is nil until the transaction is finished. The value currently is not changed on revert.
  Status is either :in_progress, :finished, {:failed_reverted, reason}.
  After finishing a transaction, the worker dispatches a message in the TransactionPubSub so the gateway can handle the message.
  """
  require Logger

  alias ExBanking.Users.UserAdapter
  alias ExBanking.Transactions.TransactionAdapter

  def start_worker(opts) do
    spawn(fn ->
      do_execute(opts)
    end)
  end

  defp do_execute(%{type: :send} = input) do
    %{sender: from_user, receiver: to_user, amount: amount, currency: currency} = input

    with {:fetch_users, {sender, receiver}}
         when sender != nil and receiver != nil <-
           {:fetch_users, {UserAdapter.get_user(from_user), UserAdapter.get_user(to_user)}},
         {:enough_funds, true} <- {:enough_funds, enough_funds?(sender, amount, currency)},
         {:create_wip_transaction, {:ok, transaction}} <-
           {:create_wip_transaction, create_in_progress_transaction(input)},
         {:ok, {_updated_transaction, updated_balances}} <-
           execute_operations(
             transaction,
             generate_operations(input, %{sender: sender, receiver: receiver})
           ) do
      finish_transaction(transaction, %{
        sender: get_updated_balance_tuple(updated_balances, from_user),
        receiver: get_updated_balance_tuple(updated_balances, to_user)
      })
    else
      error -> handle_failure([from_user, to_user], error)
    end
  end

  defp do_execute(%{type: :withdraw} = input) do
    %{sender: username, amount: amount, currency: currency} = input

    with {:fetch_user, user} when user != nil <- {:fetch_user, UserAdapter.get_user(username)},
         {:enough_funds, true} <-
           {:enough_funds, enough_funds?(user, amount, currency)},
         {:create_wip_transaction, {:ok, transaction}} <-
           {:create_wip_transaction, create_in_progress_transaction(input)},
         {:ok, {_updated_transaction, updated_balances}} <-
           execute_operations(transaction, generate_operations(input, %{sender: user})) do
      finish_transaction(transaction, %{
        sender: get_updated_balance_tuple(updated_balances, username)
      })
    else
      error -> handle_failure([username], error)
    end
  end

  defp do_execute(%{type: :deposit} = input) do
    username = input.sender

    with {:fetch_user, user} when user != nil <- {:fetch_user, UserAdapter.get_user(username)},
         {:create_wip_transaction, {:ok, transaction}} <-
           {:create_wip_transaction, create_in_progress_transaction(input)},
         {:ok, {_transaction, updated_balances}} <-
           execute_operations(transaction, generate_operations(input, %{sender: user})) do
      finish_transaction(transaction, %{
        sender: get_updated_balance_tuple(updated_balances, username)
      })
    else
      error -> handle_failure([username], error)
    end
  end

  defp generate_operations(%{type: :deposit} = input, users),
    do: {:credit, users.sender, input.currency, input.amount}

  defp generate_operations(%{type: :withdraw} = input, users),
    do: {:debit, users.sender, input.currency, input.amount}

  defp generate_operations(%{type: :send} = input, users),
    do: [
      {:debit, users.sender, input.currency, input.amount},
      {:credit, users.receiver, input.currency, input.amount}
    ]

  defp handle_failure(usernames, {:enough_funds, false}) do
    fail_transaction(usernames, :not_enough_funds)
  end

  defp handle_failure(usernames, {:error, :failed_to_update_user_balance, transaction}),
    do: fail_transaction(usernames, transaction, :failed_to_update_user_balance)

  defp handle_failure(usernames, error) do
    Logger.error("""
    Transaction failed unexpectedly. Manual operations may be required.
    usernames: #{inspect(usernames)}
    error: #{inspect(error)}
    """)

    :error
  end

  defp fail_transaction(usernames, reason) do
    dispatch_transaction({:failed_transaction, %{users: usernames, reason: reason}})
  end

  defp fail_transaction(
         usernames,
         transaction,
         :failed_to_update_user_balance
       ) do
    maybe_revert_and_update(transaction, :failed_to_update_user_balance)

    dispatch_transaction(
      {:failed_transaction, %{users: usernames, reason: :failed_to_update_user_balance}}
    )
  end

  defp maybe_revert_and_update(%{operations: operations} = transaction, reason)
       when operations != [] do
    updated_operations =
      Enum.reduce(operations, [], fn operation, acc ->
        case operation do
          %{status: status} when status != :finished ->
            [operation | acc]

          %{} ->
            :ok = revert_operation(operation)
            [Map.put(operation, :status, :reverted) | acc]
        end
      end)

    TransactionAdapter.update_transaction(transaction.id, %{
      operations: updated_operations,
      status: {:failed_reverted, reason}
    })
  end

  defp maybe_revert_and_update(transaction, reason),
    do: TransactionAdapter.update_transaction(transaction.id, %{status: {:failed, reason}})

  defp revert_operation(o) do
    # At this point, if it fails, there is no much to do other than scheduling a revert for later
    %{id: username, currencies: currencies} = UserAdapter.get_user(o.username)

    amount = get_amount_with_direction(o.direction, o.amount)

    # reverts in the opposite direction
    UserAdapter.update_user(username, Map.update!(currencies, o.currency, fn v -> v - amount end))
  end

  defp get_updated_balance_tuple(updated_balance, username),
    do: {username, Map.get(updated_balance, username)}

  defp finish_transaction(transaction, users) do
    TransactionAdapter.update_transaction(transaction.id, %{status: :finished})

    dispatch_transaction({:finished_transaction, %{users: users, type: transaction.type}})
  end

  defp dispatch_transaction({name, args}),
    do:
      Registry.dispatch(
        Registry.TransactionPubSub,
        ExBanking.Transactions.GatewayServer,
        fn subs ->
          for {pid, _} <- subs,
              do:
                send(
                  pid,
                  {name, Map.put(args, :pid, self())}
                )
        end
      )

  defp execute_operations(transaction, operations) when is_list(operations) do
    result =
      Enum.reduce_while(operations, {transaction, %{}}, fn o, {t, balances} ->
        case do_execute_operations(t, o) do
          {:ok, {updated_transaction, {username, new_balance}}} ->
            {:cont, {updated_transaction, Map.put(balances, username, new_balance)}}

          error ->
            {:halt, error}
        end
      end)

    case result do
      {:error, _, _} = error -> error
      {:error, _} = error -> error
      result -> {:ok, result}
    end
  end

  defp execute_operations(transaction, operation) do
    case do_execute_operations(transaction, operation) do
      {:ok, {updated_transaction, {username, new_balance}}} ->
        {:ok, {updated_transaction, %{username => new_balance}}}

      error ->
        error
    end
  end

  defp do_execute_operations(
         %TransactionAdapter{operations: operations} = transaction,
         {direction, %{id: username, currencies: currencies}, currency, amount}
       ) do
    amount_with_direction = get_amount_with_direction(direction, amount)

    updated_currencies =
      Map.update(currencies, currency, amount_with_direction, fn balance ->
        # subtracts when direction is :debit
        balance + amount_with_direction
      end)

    new_balance = Map.get(updated_currencies, currency)

    operation = %{
      direction: direction,
      username: username,
      currency: currency,
      amount: amount,
      updated_balance: new_balance,
      status: :finished
    }

    with {:users, :ok} <- {:users, UserAdapter.update_user(username, updated_currencies)},
         {:transaction, {:ok, updated_transaction}} <-
           {:transaction,
            TransactionAdapter.update_transaction(transaction.id, %{
              operations: [operation | operations]
            })} do
      {:ok, {updated_transaction, {username, new_balance}}}
    else
      {:users, _} -> {:error, :failed_to_update_user_balance, transaction}
      {:transaction, _} -> {:error, :failed_to_update_transaction, transaction}
    end
  end

  defp get_amount_with_direction(:debit, amount), do: -amount
  defp get_amount_with_direction(:credit, amount), do: amount

  defp enough_funds?(%{currencies: currencies}, amount, currency),
    do: Map.get(currencies, currency, 0) >= amount

  defp create_in_progress_transaction(input) do
    %TransactionAdapter{
      id: UUID.uuid4(),
      type: input.type,
      operations: [],
      status: :in_progress,
      transaction_worker: self()
    }
    |> TransactionAdapter.create_transaction()
  end
end
