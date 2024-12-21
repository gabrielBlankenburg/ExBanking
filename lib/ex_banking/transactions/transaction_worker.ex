defmodule ExBanking.Transactions.TransactionWorker do
  @moduledoc """
  Spawns a transaction, that will execute the operation.
  For each operation in a single transaction (eg. send does two ops, by removing the money from sender and adding to the receiver)
  the transaction will persist in its memory transaction table in the field `operations`.
  If the transaction fails in any step, it will look the operations and undo the transaction.
  Operations follow a pattern of {:credit | :debit, amount, currency, status, new_balance}
  The new balance is nil until the transaction is finished. The value currently is not changed on revert.
  Status is either :in_progress, :finished, {:failed_reverted, reason}.
  After finishing a transaction, the worker dispatches a message in the pubsub so the gateway can handle the message.
  """
  require Logger

  alias ExBanking.Users.UserModel
  alias ExBanking.Transactions.TransactionsTable

  def start_worker(opts) do
    spawn(fn ->
      do_execute(opts)
    end)
  end

  defp do_execute({:send, from_user, to_user, currency, amount} = input) do
    with {:fetch_users, {sender, receiver}}
         when sender != nil and receiver != nil <-
           {:fetch_users, {fetch_user(from_user), fetch_user(to_user)}},
         {:enough_funds, true} <- {:enough_funds, enough_funds?(sender, amount, currency)},
         {:create_wip_transaction, {:ok, transaction}} <-
           {:create_wip_transaction, create_in_progress_transaction(input)},
         {:ok, {_updated_transaction, updated_balances}} <-
           execute_operations(transaction, [
             {:debit, sender, currency, amount},
             {:credit, receiver, currency, amount}
           ]) do
      finish_transaction(transaction, %{
        sender: get_updated_balance_tuple(updated_balances, from_user),
        receiver: get_updated_balance_tuple(updated_balances, to_user)
      })
    else
      error -> handle_failure([from_user, to_user], error)
    end
  end

  defp do_execute({:withdraw, username, currency, amount} = input) do
    with {:fetch_user, user} when user != nil <- {:fetch_user, fetch_user(username)},
         {:enough_funds, true} <-
           {:enough_funds, enough_funds?(user, amount, currency)},
         {:create_wip_transaction, {:ok, transaction}} <-
           {:create_wip_transaction, create_in_progress_transaction(input)},
         {:ok, {_updated_transaction, updated_balances}} <-
           execute_operations(transaction, {:debit, user, currency, amount}) do
      finish_transaction(transaction, %{
        sender: get_updated_balance_tuple(updated_balances, username)
      })
    else
      error -> handle_failure([username], error)
    end
  end

  defp do_execute({:deposit, username, currency, amount} = input) do
    with {:fetch_user, user} when user != nil <- {:fetch_user, fetch_user(username)},
         {:create_wip_transaction, {:ok, transaction}} <-
           {:create_wip_transaction, create_in_progress_transaction(input)},
         {:ok, {_transaction, updated_balances}} <-
           execute_operations(transaction, {:credit, user, currency, amount}) do
      finish_transaction(transaction, %{
        sender: get_updated_balance_tuple(updated_balances, username)
      })
    else
      error -> handle_failure([username], error)
    end
  end

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
      Enum.reduce(operations, [], fn o, acc ->
        case o do
          %{status: status} when status != :finished ->
            [o | acc]

          %{} ->
            :ok = revert_operation(o)
            [Map.put(o, :status, :reverted) | acc]
        end
      end)

    TransactionsTable.update_transaction(transaction.id, %{
      operations: updated_operations,
      status: {:failed_reverted, reason}
    })
  end

  defp maybe_revert_and_update(transaction, reason),
    do: TransactionsTable.update_transaction(transaction.id, %{status: {:failed, reason}})

  defp revert_operation(o) do
    {:ok, {username, currencies}} = UserModel.get_user(o.username)

    # revert in the opposite direction
    amount = if o.direction == :debit, do: o.amount, else: -o.amount

    UserModel.update_user(username, Map.update!(currencies, o.currency, fn v -> v + amount end))
  end

  defp get_updated_balance_tuple(updated_balance, username),
    do: {username, Map.get(updated_balance, username)}

  defp finish_transaction(transaction, users) do
    TransactionsTable.update_transaction(transaction.id, %{status: :finished})

    dispatch_transaction({:finished_transaction, %{users: users, type: transaction.type}})
  end

  defp dispatch_transaction({name, args}),
    do:
      Registry.dispatch(Registry.PubSub, ExBanking.Transactions.Gateway, fn subs ->
        for {pid, _} <- subs,
            do:
              send(
                pid,
                {name, Map.put(args, :pid, self())}
              )
      end)

  defp fetch_user(username) do
    case UserModel.get_user(username) do
      {:ok, user} ->
        user

      _ ->
        nil
    end
  end

  defp execute_operations(transaction, operations) when is_list(operations) do
    Enum.reduce_while(operations, {:ok, {transaction, %{}}}, fn o, {:ok, {t, balances}} ->
      case do_execute_operations(t, o) do
        {:ok, {updated_transaction, {username, new_balance}}} ->
          {:cont, {:ok, {updated_transaction, Map.put(balances, username, new_balance)}}}

        error ->
          {:halt, error}
      end
    end)
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
         %TransactionsTable{operations: operations} = transaction,
         {direction, {username, currencies}, currency, amount}
       ) do
    parsed_amount = if direction == :debit, do: -amount, else: amount

    updated_currencies =
      Map.update(currencies, currency, parsed_amount, fn balance -> balance + parsed_amount end)

    new_balance = Map.get(updated_currencies, currency)

    with {:users, :ok} <-
           {:users,
            UserModel.update_user(
              username,
              updated_currencies
            )},
         operation <- %{
           direction: direction,
           username: username,
           currency: currency,
           amount: amount,
           updated_balance: new_balance,
           status: :finished
         },
         {:transaction, {:ok, updated_transaction}} <-
           {:transaction,
            TransactionsTable.update_transaction(transaction.id, %{
              operations: [operation | operations]
            })} do
      {:ok, {updated_transaction, {username, new_balance}}}
    else
      {:users, _} -> {:error, :failed_to_update_user_balance, transaction}
      {:transaction, _} -> {:error, :failed_to_update_transaction, transaction}
    end
  end

  defp enough_funds?({_username, currencies}, amount, currency),
    do: Map.get(currencies, currency, 0) >= amount

  defp create_in_progress_transaction(input) do
    %TransactionsTable{
      id: UUID.uuid4(),
      type: transaction_type(input),
      operations: [],
      status: :in_progress,
      transaction_worker: self()
    }
    |> TransactionsTable.create_transaction()
  end

  defp transaction_type({:send, _from_user, _to_user, _currency, _amount}), do: :send
  defp transaction_type({type, _username, _currency, _amount}), do: type
end
