defmodule HangukoWeb.Format do
  @moduledoc """
  Pure formatting helpers: values in, strings out, no markup and no socket.
  Imported everywhere `CoreComponents` is, so a count or an interval reads
  the same wherever it's shown instead of every page growing its own
  formatter.
  """

  @doc """
  Returns a formatted object count binary, handling pluralization.

      iex> HangukoWeb.Format.format_count(1, "ball")
      "1 ball"
      iex> HangukoWeb.Format.format_count(2, "orange")
      "2 oranges"
  """
  def format_count(1, noun), do: "1 #{noun}"
  def format_count(n, noun), do: "#{format_number(n)} #{noun}s"

  @doc """
  Returns a formatted number, ensuring commas are placed correctly

      iex> HangukoWeb.Format.format_number(100)
      "100"
      iex> HangukoWeb.Format.format_number(2000)
      "2,000"
  """
  def format_number(n) do
    n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  @doc """
  Formats an interval in seconds compactly: `"1m"`, `"10m"`, `"3h"`, `"4d"`,
  `"2.5mo"`, `"1.2y"`.

      iex> HangukoWeb.Format.format_interval(90)
      "1m"
      iex> HangukoWeb.Format.format_interval(4 * 86_400)
      "4d"
  """
  def format_interval(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "<1m"
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{round(seconds / 3600)}h"
      seconds < 30 * 86_400 -> "#{round(seconds / 86_400)}d"
      seconds < 365 * 86_400 -> "#{decimal(seconds / (30 * 86_400))}mo"
      true -> "#{decimal(seconds / (365 * 86_400))}y"
    end
  end

  defp decimal(value) do
    rounded = Float.round(value, 1)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end
end
