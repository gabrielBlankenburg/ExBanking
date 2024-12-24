defmodule ExBanking.Transactions.TransactionsTable do
  @moduledoc """
  Holds the transactions ets table
  """
  require Logger

  alias ExBanking.Common.ETS

  @table_name :transactions

  def start_link, do: init()

  def table_name, do: @table_name

  def create_transaction(data) do
    if :ets.insert_new(@table_name, data) do
      {:ok, data}
    else
      {:error, :transaction_already_exists}
    end
  end

  def get_transaction(id), do: ETS.get_by_id(@table_name, id)

  def update_transaction(id, data) do
    if :ets.update_element(@table_name, id, data) do
      :ok
    else
      {:error, :failed_to_update_transaction}
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
