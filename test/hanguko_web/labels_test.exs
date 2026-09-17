defmodule HangukoWeb.LabelsTest do
  use ExUnit.Case, async: true

  alias Hanguko.Content.Deck
  alias Hanguko.Content.Item
  alias Hanguko.SRS.Card
  alias HangukoWeb.Labels

  describe "template_label/1" do
    test "has a label for every card template" do
      for template <- Card.templates() do
        assert is_binary(Labels.template_label(template))
      end
    end
  end

  describe "state_label/1" do
    test "has a label for every card state" do
      for state <- Card.states() do
        assert is_binary(Labels.state_label(state))
      end
    end
  end

  describe "deck_kind_label/1" do
    test "has a label for every deck kind" do
      for kind <- Deck.kinds() do
        assert is_binary(Labels.deck_kind_label(kind))
      end
    end
  end

  describe "politeness_label/1" do
    test "has a label for every politeness level" do
      for level <- Item.politeness_levels() do
        assert is_binary(Labels.politeness_label(level))
      end
    end

    test "is nil for a nil level" do
      assert Labels.politeness_label(nil) == nil
    end

    test "raises for an unrecognized level" do
      assert_raise ArgumentError, fn -> Labels.politeness_label("blunt") end
    end
  end
end
