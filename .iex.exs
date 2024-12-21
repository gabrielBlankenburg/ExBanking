alias ExBanking.Transactions.Gateway
alias ExBanking.Transactions.TransactionsTable
alias ExBanking.Users.UsersTable

require Logger

UsersTable.create_user("john")
UsersTable.create_user("doe")
Gateway.deposit("john", 30, "usd")
IO.inspect(Gateway.send_money("john", "doe", 10, "usd"))

users = ["john", "mike", "doe"]
currencies = ["usd", "brl", "btc", "doge"]
invalid_users = []

send_operation = fn from, amount, currency ->
  to = Enum.random(users ++ invalid_users)
  Gateway.send_money(from, to, amount, currency)
end

deposit_operation = fn from, amount, currency ->
  Gateway.deposit(from, amount, currency)
end

withdraw_operation = fn from, amount, currency ->
  Gateway.withdraw(from, amount, currency)
end

ops = [{:send, send_operation}, {:deposit, deposit_operation}, {:withdraw, withdraw_operation}]
ops = [{:deposit, deposit_operation}]

spawn_op = fn fun, name, from, amount, currency ->
  spawn(fn ->
    {name, r} = {name, fun.(from, amount, currency)}
    if r == {:error, :too_many_requests_to_user}, do: IO.inspect(r)
  end)
end

Enum.each(users, fn u ->
  currency = Enum.random(currencies)
  value = Enum.random(1..30)
  UsersTable.create_user(u)
  Gateway.deposit(u, value, currency)
end)

1..100_000
|> Enum.each(fn _ ->
  user = Enum.random(users ++ invalid_users)
  amount = Enum.random(1..30)
  currency = Enum.random(currencies)

  {op, fun} = Enum.random(ops)

  spawn_op.(fun, op, user, amount, currency)
end)


# UsersTable.create_user("john")
# UsersTable.create_user("ledger")
# Gateway.deposit("ledger", 1_000_000, "usd")
# operations = [
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.withdraw("john", 10, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.withdraw("john", 20, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.deposit("john", 20, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.send_money("ledger", "john", 10, "usd") end,
#   fn -> Gateway.send_money("john", "ledger", 10, "usd") end,
#   fn -> Gateway.withdraw("john", 100000000, "usd") end,
# ]

# operations |> Enum.each(fn o ->
#   spawn(fn ->
#     IO.inspect({o, o.()})
#   end)
# end)


# 1..100 |> Enum.each(fn _ ->
#   spawn(fn ->
#     IO.inspect(Gateway.send_money("ledger", "john", 10, "usd"))
#   end)
# end)


# ops = [
#   {:send, fn v -> Gateway.send_money("ledger", "john", v, "usd") end},
#   {:deposit, fn v -> Gateway.deposit("john", v, "usd") end},
#   {:withdraw, fn v -> Gateway.withdraw("john", v, "usd") end},
# ]

# 1..40 |> Enum.each(fn v ->
#   spawn(fn ->
#     {name, fun} = Enum.random(ops)

#     IO.inspect({name, fun.(v * 10)})
#   end)
# end)
