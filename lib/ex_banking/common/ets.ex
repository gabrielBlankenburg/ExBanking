defmodule ExBanking.Common.ETS do
  def get_by_id(table, id) do
    case :ets.lookup(table, id) do
      [] -> {:error, :not_found}
      [result] -> {:ok, result}
    end
  end
end
