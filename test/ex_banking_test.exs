defmodule ExBankingTest do
  use ExUnit.Case

  alias ExBanking.Users.UserModel

  test "creates a user sucessfully when providing proper arguments" do
    username = "valid_user"
    assert :ok == ExBanking.create_user(username)
    assert {:ok, {^username, %{}}} = UserModel.get_user(username)
  end

  test "fails with {:error, :user_already_exists} when trying to duplicate user" do
    username = "duplicated_user"
    assert :ok == ExBanking.create_user(username)
    assert {:ok, {^username, %{}}} = UserModel.get_user(username)
    assert {:error, :user_already_exists} == ExBanking.create_user(username)
  end

  test "deposit money sucessfully" do
    username = "deposit_test"
    assert :ok == ExBanking.create_user(username)
    assert {:ok, 10} == ExBanking.deposit(username, 10, "usd")
  end

  test "fail to deposit money with invalid args" do
    assert {:error, :wrong_arguments} == ExBanking.deposit(:invalid_type, 10, "usd")
    assert {:error, :wrong_arguments} == ExBanking.deposit("some_user", -10, "usd")
    assert {:error, :wrong_arguments} == ExBanking.deposit("some_user", 10, :usd)
  end

  test "fail to deposit money with unexisting user" do
    assert {:error, :user_does_not_exist} == ExBanking.deposit("not in our memory", 10, "usd")
  end

  test "withdraw money sucessfully" do
    username = "withdraw_test"
    ExBanking.create_user(username)
    ExBanking.deposit(username, 10, "usd")
    assert {:ok, 0} = ExBanking.withdraw(username, 10, "usd")
  end

  test "fail to withdraw money with invalid args" do
    assert {:error, :wrong_arguments} == ExBanking.withdraw(:invalid_type, 10, "usd")
    assert {:error, :wrong_arguments} == ExBanking.withdraw("some_user", -10, "usd")
    assert {:error, :wrong_arguments} == ExBanking.withdraw("some_user", 10, :usd)
  end

  test "fail to withdraw money with unexisting user" do
    assert {:error, :user_does_not_exist} == ExBanking.withdraw("not in our memory", 10, "usd")
  end

  test "fail to withdraw money with not enough funds" do
    username = "withdraw_without_funds"
    ExBanking.create_user(username)
    ExBanking.deposit(username, 10, "usd")

    assert {:error, :not_enough_funds} == ExBanking.withdraw(username, 11, "usd")
    assert {:error, :not_enough_funds} == ExBanking.withdraw(username, 1, "brl")
  end

  test "send money sucessfully" do
    sender = "sender"
    receiver = "receiver"

    ExBanking.create_user(sender)
    ExBanking.create_user(receiver)
    ExBanking.deposit(sender, 10, "usd")

    assert {:ok, 0, 10} = ExBanking.send(sender, receiver, 10, "usd")
  end

  test "fail to send money when sender does not have enough funds" do
    sender = "sender_without_funds"
    receiver = "receiver_wont_receive_money"

    ExBanking.create_user(sender)
    ExBanking.create_user(receiver)
    ExBanking.deposit(sender, 10, "usd")

    assert {:error, :not_enough_funds} = ExBanking.send(sender, receiver, 11, "usd")
    assert {:error, :not_enough_funds} = ExBanking.send(sender, receiver, 11, "brl")
  end

  test "fail scenarios for send" do
    sender = "valid_sender"
    receiver = "valid_receiver"

    ExBanking.create_user(sender)
    ExBanking.create_user(receiver)

    assert {:error, :wrong_arguments} = ExBanking.send(:sender, receiver, 11, "usd")
    assert {:error, :wrong_arguments} = ExBanking.send(sender, :receiver, 11, "usd")
    assert {:error, :wrong_arguments} = ExBanking.send(sender, receiver, 0, "usd")
    assert {:error, :wrong_arguments} = ExBanking.send(:sender, receiver, 11, :brl)
    assert {:error, :sender_not_found} = ExBanking.send("dont exist", receiver, 11, "usd")
    assert {:error, :receiver_not_found} = ExBanking.send(sender, "dont exist", 11, "usd")
  end
end
