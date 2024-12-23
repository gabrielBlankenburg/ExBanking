defmodule ExBanking.Transactions.TransactionAdapter do
  @moduledoc """
  An adapter that handles the ets transaction table properly
  """
  alias ExBanking.Transactions.TransactionsTable

  defstruct [
    :id,
    :type,
    :operations,
    :status,
    :transaction_worker
  ]

  @fields_to_ets_pos %{
    type: 2,
    operations: 3,
    status: 4,
    transaction_worker: 5
  }

  @doc """
  Creates a new transaction on ets
  """
  @spec create_transaction(%ExBanking.Transactions.TransactionAdapter{}) ::
          {:error, :transaction_already_exists}
          | {:ok,
             %ExBanking.Transactions.TransactionAdapter{
               id: any(),
               operations: any(),
               status: any(),
               transaction_worker: any(),
               type: any()
             }}
  def create_transaction(%__MODULE__{} = input) do
    data = {input.id, input.type, input.operations, input.status, input.transaction_worker}

    case TransactionsTable.create_transaction(data) do
      {:ok, r} -> {:ok, parse_ets_data(r)}
      {:error, :transaction_already_exists} -> {:error, :transaction_already_exists}
    end
  end

  @doc """
  Gets a transaction
  """
  @spec get_transaction(binary()) ::
          nil
          | %ExBanking.Transactions.TransactionAdapter{
              id: binary(),
              operations: list(tuple()),
              status: :in_progress | :finished | {:failed | :failed_reverted, atom()},
              transaction_worker: pid(),
              type: :send | :deposit | :withdraw
            }
  def get_transaction(id) do
    case TransactionsTable.get_transaction(id) do
      {:ok, result} ->
        parse_ets_data(result)

      {:error, :not_found} ->
        nil
    end
  end

  @doc """
  Updates a transaction, the kvs, are the field(s) to be changed as key and new values as values
  """
  @spec update_transaction(binary(), map()) ::
          {:error, :failed_to_update_transaction | :no_valid_fields_to_update}
          | {:ok,
             %ExBanking.Transactions.TransactionAdapter{
               id: binary(),
               operations: list(),
               status: :finished | :in_progress | {:failed | :failed_reverted, atom()},
               transaction_worker: pid(),
               type: :deposit | :send | :withdraw
             }}
  def update_transaction(id, %{} = kvs) do
    with {:ok, result} <- parse_update_args(kvs),
         :ok <- TransactionsTable.update_transaction(id, result),
         parsed_transaction when not is_nil(parsed_transaction) <- get_transaction(id) do
      {:ok, parsed_transaction}
    else
      {:error, :no_valid_fields_to_update} ->
        {:error, :no_valid_fields_to_update}

      {:error, :failed_to_update_transaction} ->
        {:error, :failed_to_update_transaction}
    end
  end

  defp parse_update_args(kvs), do: parse_update_args(Enum.to_list(kvs), [])
  defp parse_update_args([], []), do: {:error, :no_valid_fields_to_update}
  defp parse_update_args([], data), do: {:ok, data}

  defp parse_update_args([{k, value} | tail], data) do
    case(Map.get(@fields_to_ets_pos, k)) do
      nil -> parse_update_args(tail, data)
      pos -> parse_update_args(tail, [{pos, value} | data])
    end
  end

  defp parse_ets_data({id, type, operations, status, transaction_worker}) do
    %__MODULE__{
      id: id,
      type: type,
      operations: operations,
      status: status,
      transaction_worker: transaction_worker
    }
  end
end
