defmodule ExBanking.Common.Money do
  @moduledoc """
  Converts float to decimal and vice versa. Useful for sending proper integer numbers for operations and showing decimal
  for users
  """
  @decimal_precision 2

  @doc """
  Parses a number into an integer representation of a decimal, the decimal precision is defined by `@decimal_presicion`.
  """
  @spec parse(number :: number()) :: {:ok, integer()} | :error
  def parse(number) when is_integer(number), do: {:ok, number * 100}

  def parse(number) when is_float(number) do
    multilpier = get_decimal()

    parsed_decimal = Float.round(number, @decimal_precision)

    {:ok, round(parsed_decimal * multilpier)}
  end

  def parse(_), do: :error

  @doc """
  Converts an integer representation of a float into a float with a precision of `@decimal_precision`
  """
  @spec to_float!(money :: integer()) :: float()
  def to_float!(money) when is_integer(money) do
    divider = get_decimal()

    Float.round(money / divider, @decimal_precision)
  end

  defp get_decimal, do: 10 |> :math.pow(@decimal_precision) |> round()
end
