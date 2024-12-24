defmodule ExBanking.Transactions.Gateway do
  @moduledoc """
  The Gateway is a server responsible for rate limiting, enqueing, and dispatching banking operations.
  Its state is composed by a tuple {users_state, transactions_state}
  The users state is a map, where the key is the username (key in users table) and the value is another map with:
    - transactions_queue: list of enqueued operations. After user is released it will execute the next transaction.
    - transactios_queue_count: it is the value of the enqued list + the current operation (if any)
    - status: :available or :unavailable, it will tell if the user can execute the transaction right away, or wait for
    an ongoing transaction
    - id: same as the key for simplyfing some flows
    Note: when executing a send operation, it will only start when both users are available, as well as it will lock both users.
    However, enqueued send transactions will only increment the transactions_queue_count of the sender.
  The transactions state, is a map, where the id is a pid process from `ExBanking.Transactions.TransactionWorker` and the
  value is the client who called this server.
  Every time a user is available and there is a pending transaction for they, this server will dispatch a new worker that will
  only execute that operation, and dispatch messages via registry after finishing, failing or reverting a transaction.
  The operations are sending, depositing, and withdrawing money, as well as getting balance.
  The get balance is the only operation that does not spawn any new worker, instead it will just call the users table
  and return the balance result. This decision was made because this server validates if the user exists before spawning
  a new transaction. In case of getting the balance, the query is pretty much the same with a few handling of the result.
  Hence, as the project grows, it might be worth relying only in the transactions to check if user exists.
  This server is registered in the TransactionPubSub that dispatches when a transaction is finished or failed. In both cases, the server
  will take the transaction data, lookup its state, replying the client stored in the `transactions_state` and removing it from
  the state, also decrementing the operations count and calling the next user operation for that user.

  TODO
  Lookup the transactions table on init to reconstruct its state on restarts. Worth to note that the transactions_queue would be
  lost, but we could still lock the proper users doing transactions. The lost queue would result in just a timeout for clients as
  the operations would not be started
  """
  use GenServer
  require Logger

  alias ExBanking.Transactions.TransactionWorker
  alias ExBanking.Users.UserAdapter

  defguard is_valid_input(sender, currency) when is_binary(sender) and is_binary(currency)

  defguard is_valid_input(sender, amount, currency)
           when is_binary(sender) and is_number(amount) and amount > 0 and is_binary(currency)

  defguard is_valid_input(sender, receiver, amount, currency)
           when is_binary(sender) and is_binary(receiver) and sender != receiver and
                  is_number(amount) and
                  amount > 0 and is_binary(currency)

  @max_transactions_queue_for_user 10
  @default_user_state %{
    transactions_queue: [],
    transactions_queue_count: 0,
    status: :available,
    id: nil
  }

  # Client

  def start_link, do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def send_money(sender, receiver, amount, currency)
      when is_valid_input(sender, receiver, amount, currency),
      do: GenServer.call(__MODULE__, {:send, sender, receiver, currency, amount})

  def send_money(_sender, _receiver, _amount, _currency),
    do: {:error, :wrong_arguments}

  def deposit(sender, amount, currency) when is_valid_input(sender, amount, currency),
    do: GenServer.call(__MODULE__, {:deposit, sender, currency, amount})

  def deposit(_sender, _amount, _currency), do: {:error, :wrong_arguments}

  def withdraw(sender, amount, currency) when is_valid_input(sender, amount, currency),
    do: GenServer.call(__MODULE__, {:withdraw, sender, currency, amount})

  def withdraw(_sender, _amount, _currency), do: {:error, :wrong_arguments}

  def get_balance(username, currency) when is_valid_input(username, currency),
    do: GenServer.call(__MODULE__, {:get_balance, username, currency})

  def get_balance(_username, _currency),
    do: {:error, :wrong_arguments}

  # Server

  @impl true
  def init(_) do
    users = %{}
    transactions_in_progress = %{}
    Registry.register(Registry.TransactionPubSub, __MODULE__, [])
    {:ok, {users, transactions_in_progress}}
  end

  @impl true
  def handle_call(
        {:send, _from_user, _to_user, _currency, _amount} = new_transaction,
        client,
        state
      ) do
    case execute_transaction(new_transaction, client, state) do
      {:ok, state} -> {:noreply, state}
      {:error, msg, state} -> {:reply, {:error, msg}, state}
    end
  end

  def handle_call(
        {type, _username, _currency, _amount} = new_transaction,
        client,
        state
      )
      when type in [:deposit, :withdraw] do
    case execute_transaction(new_transaction, client, state) do
      {:ok, state} -> {:noreply, state}
      {:error, msg, state} -> {:reply, {:error, msg}, state}
    end
  end

  def handle_call(
        {:get_balance, _username, _currency} = new_transaction,
        client,
        state
      ) do
    case execute_transaction(new_transaction, client, state) do
      {:ok, state} -> {:noreply, state}
      {:error, msg, state} -> {:reply, {:error, msg}, state}
    end
  end

  def handle_call(_, _client, state), do: {:reply, {:error, :unhandled_call, state}}

  @impl true
  def handle_cast(_, state), do: {:noreply, state}

  # Call next for sender and receiver, also responds the client waiting for the transaction of the transaction_pid
  @impl true
  def handle_info(
        {:finished_transaction,
         %{
           users: %{sender: {sender, sender_balance}, receiver: {receiver, receiver_balance}},
           pid: transaction_pid
         }},
        {users_state, transactions_state}
      ) do
    updated_transactions_state =
      case Map.pop(transactions_state, transaction_pid) do
        {nil, result} ->
          Logger.error(
            "Transaction finished, but gateway does not have its caller in state. transaction_pid: #{inspect(transaction_pid)}"
          )

          result

        {pid, result} ->
          GenServer.reply(pid, {:ok, sender_balance, receiver_balance})

          result
      end

    next(sender)
    next(receiver)

    updated_users_state =
      [sender, receiver]
      |> update_users_status(users_state, :available)
      |> Map.update(sender, default_user_state(sender), fn user ->
        if user.transactions_queue_count > 1 do
          Map.put(user, :transactions_queue_count, user.transactions_queue_count - 1)
        else
          Map.put(user, :transactions_queue_count, 0)
        end
      end)

    {:noreply, {updated_users_state, updated_transactions_state}}
  end

  def handle_info(
        {:finished_transaction,
         %{type: type, users: %{sender: {username, balance}}, pid: transaction_pid}},
        {users_state, transactions_state}
      )
      when type in [:deposit, :withdraw] do
    updated_transactions_state =
      case Map.pop(transactions_state, transaction_pid) do
        {nil, result} ->
          Logger.error(
            "Transaction finished, but gateway does not have its caller in state. transaction_pid: #{inspect(transaction_pid)}}"
          )

          result

        {pid, result} ->
          GenServer.reply(pid, {:ok, balance})

          result
      end

    next(username)

    {:noreply, {users_state, updated_transactions_state}}
  end

  def handle_info(
        {:failed_transaction, %{pid: pid, users: users, reason: reason}},
        {users_state, transactions_state}
      ) do
    Enum.each(users, &next/1)

    response =
      if reason == :not_enough_funds, do: {:error, :not_enough_funds}, else: {:error, :unexpected}

    {client, updated_transactions_state} = Map.pop(transactions_state, pid)

    GenServer.reply(client, response)

    {:noreply, {users_state, updated_transactions_state}}
  end

  # Decrements the transactions queue count and execute the next transaction if necessary (and possible)
  def handle_info({:next, username}, {users_state, transactions_state}) do
    case Map.get(users_state, username) do
      %{
        transactions_queue: [{transaction, client} | queue],
        transactions_queue_count: count
      } =
          user_state ->
        updated_user_state =
          user_state
          |> Map.put(:transactions_queue, queue)
          |> Map.put(:transactions_queue_count, count - 1)
          |> Map.put(:status, :available)

        case execute_transaction(
               transaction,
               client,
               {Map.put(users_state, username, updated_user_state), transactions_state}
             ) do
          {:ok, state} ->
            {:noreply, state}

          {:error, msg, state} ->
            GenServer.reply(client, msg)
            {:noreply, state}
        end

      user_state ->
        updated_user_state =
          user_state
          |> Map.put(:status, :available)
          |> Map.put(:transactions_queue_count, 0)

        {:noreply, {Map.put(users_state, username, updated_user_state), transactions_state}}
    end
  end

  def handle_info(msg, state) do
    Logger.warning("Ignoring unhandled message #{inspect(msg)}")
    {:noreply, state}
  end

  defp execute_transaction(
         {:send, from_user, to_user, _currency, _amount} = new_transaction,
         client,
         {users_state, transactions_state} = state
       ) do
    usernames = [from_user, to_user]

    with {available_users_state, users} <- init_users_states(usernames, users_state),
         {:users_available, true} <- {:users_available, users_available?(users)},
         updated_users_state <-
           update_users_status(usernames, available_users_state, :unavailable),
         updated_users_state <- increment_user_queue_count(updated_users_state, from_user),
         {:get_users, {{:ok, _sender}, _}, {{:ok, _receiver}, _}} <-
           {:get_users, {UserAdapter.get_user(from_user), from_user},
            {UserAdapter.get_user(to_user), to_user}},
         updated_transactions_state <-
           start_transaction(new_transaction, client, transactions_state) do
      {:ok, {updated_users_state, updated_transactions_state}}
    else
      {:get_users, {{:error, :user_does_not_exist}, username}, _} when username == from_user ->
        {:error, :sender_not_found, {Map.delete(users_state, username), transactions_state}}

      {:get_users, _, {{:error, :user_does_not_exist}, username}} when username == to_user ->
        {:error, :receiver_not_found, {Map.delete(users_state, username), transactions_state}}

      {:users_available, false} ->
        user_state = Map.get(users_state, from_user, default_user_state(from_user))

        if user_has_queue_limit?(user_state) do
          updated_users_state =
            enqueue_operation_for_user(new_transaction, user_state, client, users_state)

          {:ok, {updated_users_state, transactions_state}}
        else
          {:error, :too_many_requests_to_user, state}
        end
    end
  end

  defp execute_transaction(
         {type, username, _currency, _amount} = new_transaction,
         client,
         {users_state, transactions_state} = state
       )
       when type in [:deposit, :withdraw] do
    with {available_users_state, users} <- init_users_states(username, users_state),
         {:users_available, true} <- {:users_available, users_available?(users)},
         updated_users_state <-
           update_users_status(username, available_users_state, :unavailable),
         updated_users_state <- increment_user_queue_count(updated_users_state, username),
         {:get_user, {:ok, _username}} <- {:get_user, UserAdapter.get_user(username)},
         updated_transactions_state <-
           start_transaction(new_transaction, client, transactions_state) do
      {:ok, {updated_users_state, updated_transactions_state}}
    else
      {:get_user, {:error, :user_does_not_exist}} ->
        {:error, :user_does_not_exist, {Map.delete(users_state, username), transactions_state}}

      {:users_available, false} ->
        user_state = Map.get(users_state, username, default_user_state(username))

        if user_has_queue_limit?(user_state) do
          updated_users_state =
            enqueue_operation_for_user(new_transaction, user_state, client, users_state)

          {:ok, {updated_users_state, transactions_state}}
        else
          {:error, :too_many_requests_to_user, state}
        end
    end
  end

  # Does not dispatch a transaction. It will simply look the user balance
  defp execute_transaction(
         {:get_balance, username, currency} = new_transaction,
         client,
         {users_state, transactions_state} = state
       ) do
    with {available_users_state, users} <- init_users_states(username, users_state),
         {:users_available, true} <- {:users_available, users_available?(users)},
         updated_users_state <-
           update_users_status(username, available_users_state, :unavailable),
         updated_users_state <- increment_user_queue_count(updated_users_state, username),
         {:ok, new_balance} <- UserAdapter.get_balance(username, currency) do
      GenServer.reply(client, {:ok, new_balance})

      next(username)

      {:ok, {updated_users_state, transactions_state}}
    else
      {:error, :user_does_not_exist} ->
        {:error, :user_does_not_exist, {Map.delete(users_state, username), transactions_state}}

      {:error, :wrong_arguments} ->
        {:error, :wrong_arguments, state}

      {:users_available, false} ->
        user_state = Map.get(users_state, username, default_user_state(username))

        if user_has_queue_limit?(user_state) do
          updated_users_state =
            enqueue_operation_for_user(new_transaction, user_state, client, users_state)

          {:ok, {updated_users_state, transactions_state}}
        else
          {:error, :too_many_requests_to_user, state}
        end
    end
  end

  defp increment_user_queue_count(users_state, username),
    do:
      Map.update!(
        users_state,
        username,
        &Map.update!(&1, :transactions_queue_count, fn count -> count + 1 end)
      )

  defp enqueue_operation_for_user(transaction, user, client, available_users_state) do
    updated_user =
      user
      |> Map.update!(:transactions_queue, fn queue -> [{transaction, client} | queue] end)
      |> Map.update!(:transactions_queue_count, fn count -> count + 1 end)

    Map.put(available_users_state, user.id, updated_user)
  end

  # Inits a single user or a user list, it also updates the state in case the func calling it needs
  defp init_users_states(username, users_state) when not is_list(username),
    do: init_users_states([username], users_state)

  defp init_users_states(usernames, users_state) do
    Enum.reduce(usernames, {users_state, []}, fn username, {state, users_state} ->
      user_state = Map.get(state, username, default_user_state(username))

      {Map.put(state, username, user_state), [user_state | users_state]}
    end)
  end

  defp users_available?(users) do
    Enum.reduce_while(users, true, fn u, _acc ->
      if u.status == :unavailable do
        {:halt, false}
      else
        {:cont, true}
      end
    end)
  end

  # Preventing too many requests
  defp user_has_queue_limit?(%{transactions_queue_count: count})
       when count < @max_transactions_queue_for_user,
       do: true

  defp user_has_queue_limit?(_user), do: false

  defp update_users_status(username, users_state, status) when not is_list(username),
    do: update_users_status([username], users_state, status)

  defp update_users_status(usernames, users_state, status) do
    Enum.reduce(usernames, users_state, fn username, acc ->
      user = Map.get(acc, username, default_user_state(username))

      user_state =
        Map.put(user, :status, status)

      Map.put(acc, username, user_state)
    end)
  end

  # Dispatches a new transaction and update the transactions state with the pid of the worker and the client
  # waiting for the response
  defp start_transaction(new_transaction, client, transactions_state) do
    transaction_pid =
      TransactionWorker.start_worker(new_transaction)

    Map.put(transactions_state, transaction_pid, client)
  end

  defp default_user_state(id), do: Map.put(@default_user_state, :id, id)

  defp next(username), do: send(self(), {:next, username})
end
