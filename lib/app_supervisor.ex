defmodule ExBanking.AppSupervisor do
  use Application

  @doc """
  The Applications supervisor is designed as follows:
  - The first child is the :users_table_server. It holds all users and should not be affected by other process failures.
    Every other child (except :transactions_registry) depends on this child. So if this child is restarted, every other child
    needs restarting
  - The :transactions_pub_sub is a simple registry used for dispatching messages from workers to the Gateway.
  - The :transactions_table_server holds every transaction from users
  - The :gateway holds in its state the transactions enqueued and rate limit. It is started after the :transactions_table_server,
  because on restarts, it can lookup in progress transactions and partially rebuild its state. The enqueued transactions will
  be lost, hence it means that no money movement was done for these lost transactions.
  """
  @spec start(any(), any()) :: {:error, any()} | {:ok, pid()}
  def start(_type, _args) do
    children = [
      %{id: :users_table_server, start: {ExBanking.Users.UsersTable, :start_link, []}},
      %{
        id: :transactions_pub_sub,
        start: {Registry, :start_link, [[keys: :duplicate, name: Registry.TransactionPubSub]]}
      },
      %{
        id: :transactions_table_server,
        start: {ExBanking.Transactions.TransactionsTable, :start_link, []}
      },
      %{id: :gateway, start: {ExBanking.Transactions.GatewayClient, :start_link, []}}
    ]

    Supervisor.start_link(children, strategy: :rest_for_one, name: __MODULE__)
  end
end
