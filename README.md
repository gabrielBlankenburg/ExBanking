# ExBanking

## How it works
The app supervisor uses a `:rest_for_one` strategy, so if the most importante children stops, all the following ones restarts too.

This app uses two ets tables: `:transactions` and `:users`. They are both public, but the gateway prevents horse conditions.
The users simply holds a map of currencies and balances for those currencies, the transactions keep the operations in a transaction, the worker pid responsible for that transaction (will be useful for the future transaction health checker), and other data required for keeping the transaction state.

We have the Gateway that handles any banking operation. Its state holds the Transaction Workers running and the clients waiting for their response. It will handle only one transaction for each user at the same time. If the same user attempts to make multiple banking operations while there is an ongoing transaction, the Gateway will enqueue the new requests, limiting the queue to maximum of 10 requests. If an user sends money to another user, both will be locked, but enqueued operations of transfering money does not increase the queue count for receivers.
Note: As the project scales this server might need a better replication, since it is a single point of failure.

The Transaction Worker handles a single transaction. When it fails (without the server going down) it will revert the finished operations. Before a normal exit the server dispatches messages for TransactionsPubSub so the Gateway (and a future transactions health checker) take action of updating its state and replying the proper client, as well as starting the next operation for the users.

## TODO
- Make the Gateway partially recover its state on restart;
- Create a health server, that checks peridically if the persisted wip transactions have their worker pid alive,
otherwise, it should reverted the finished operations and release the users on gateway;
- Separate better the logic of ets tables and their models.
