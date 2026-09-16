defmodule HangukoWeb.Format do
  @moduledoc """
  Common formatting helpers for web components.
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
      "1"
      iex> HangukoWeb.Format.format_number(2000)
      "2,000"
  """
  def format_number(n) do
    n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end
end
