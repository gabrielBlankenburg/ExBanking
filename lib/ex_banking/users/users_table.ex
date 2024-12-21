defmodule ExBanking.Users.UsersTable do
  @moduledoc """
  Holds the transactions ets table
  """
  alias ExBanking.Common.ETS

  @table_name :users

  def start_link, do: init()

  def create_user(username) when is_binary(username) do
    if :ets.insert_new(@table_name, {username, %{}}) do
      :ok
    else
      {:error, :user_already_exists}
    end
  end

  def get_user(username) when is_binary(username),
    do: ETS.get_by_id(@table_name, username)

  def update_user(username, currencies) do
    if :ets.update_element(@table_name, username, {2, currencies}) do
      :ok
    else
      {:error, :not_found}
    end
  end

  def table_name, do: @table_name

  # Table Server
  defp init() do
    pid =
      spawn(fn ->
        :ets.new(@table_name, [:set, :public, :named_table])
        loop()
      end)

    {:ok, pid}
  end

  defp loop() do
    loop()
  end
end
