defmodule ExBanking.Transactions.TransactionsTable do
  @moduledoc """
  Holds the transactions ets table
  """
  require Logger

  alias ExBanking.Common.ETS

  @table_name :transactions

  @fields_to_ets_pos %{
    type: 2,
    operations: 3,
    status: 4,
    transaction_worker: 5
  }

  defstruct [
    :id,
    :type,
    :operations,
    :status,
    :transaction_worker
  ]

  def start_link, do: init()

  def table_name, do: @table_name

  def create_transaction(%__MODULE__{} = input) do
    data = {input.id, input.type, input.operations, input.status, input.transaction_worker}

    if :ets.insert_new(@table_name, data) do
      {:ok, parse_ets_data(data)}
    else
      {:error, :existing_transaction_id}
    end
  end

  def get_transaction(id) do
    case ETS.get_by_id(@table_name, id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, {_id, _type, _operations, _status, _transaction_worker} = result} ->
        parse_ets_data(result)
    end
  end

  def update_transaction(id, %{} = kvs) do
    with {:parse_kvs, {:ok, result}} <- {:parse_kvs, parse_update_args(kvs)},
         {:update_ets_table, true} <-
           {:update_ets_table, :ets.update_element(@table_name, id, result)},
         {:get_transaction, transaction} <- {:get_transaction, get_transaction(id)} do
      {:ok, transaction}
    else
      {:parse_kvs, {:error, :no_valid_fields_to_update}} ->
        {:error, :no_valid_fields_to_update}

      {:update_ets_table, false} ->
        {:error, :not_found}
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

  defp parse_update_args(kvs), do: parse_update_args(Enum.to_list(kvs), [])
  defp parse_update_args([], []), do: {:error, :no_valid_fields_to_update}
  defp parse_update_args([], data), do: {:ok, data}

  defp parse_update_args([{k, value} | tail], data) do
    case(Map.get(@fields_to_ets_pos, k)) do
      nil -> parse_update_args(tail, data)
      pos -> parse_update_args(tail, [{pos, value} | data])
    end
  end

  # Table Server
  defp init() do
    pid =
      spawn(fn ->
        :ets.new(table_name(), [:set, :public, :named_table])
        loop()
      end)

    {:ok, pid}
  end

  defp loop() do
    loop()
  end
end
