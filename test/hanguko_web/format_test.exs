defmodule HangukoWeb.FormatTest do
  use ExUnit.Case, async: true

  alias HangukoWeb.Format

  doctest Format

  describe "format_count/2" do
    test "uses the singular noun for a count of 1" do
      assert Format.format_count(1, "ball") == "1 ball"
    end

    test "pluralizes the noun and formats the count for other values" do
      assert Format.format_count(0, "ball") == "0 balls"
      assert Format.format_count(2, "orange") == "2 oranges"
      assert Format.format_count(1000, "point") == "1,000 points"
    end
  end

  describe "format_number/1" do
    test "leaves numbers under a thousand unchanged" do
      assert Format.format_number(0) == "0"
      assert Format.format_number(100) == "100"
    end

    test "inserts commas every three digits" do
      assert Format.format_number(1000) == "1,000"
      assert Format.format_number(2000) == "2,000"
      assert Format.format_number(1_234_567) == "1,234,567"
    end
  end
end
