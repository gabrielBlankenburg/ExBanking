defmodule ExBanking.Common.ETS do
  @moduledoc """
  Abstracts shared logic between ets clients queries
  """
  @spec get_by_id(atom() | :ets.tid(), any()) :: {:error, :not_found} | {:ok, tuple()}
  def get_by_id(table, id) do
    case :ets.lookup(table, id) do
      [] -> {:error, :not_found}
      [result] -> {:ok, result}
    end
  end
end
