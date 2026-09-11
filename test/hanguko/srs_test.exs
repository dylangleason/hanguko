defmodule Hanguko.SRSTest do
  use Hanguko.DataCase, async: true

  import Hanguko.AccountsFixtures
  import Hanguko.ContentFixtures

  alias Hanguko.SRS

  describe "deck enrollment" do
    test "is per user and idempotent" do
      scope = user_scope_fixture()
      other = user_scope_fixture()
      deck = deck_fixture()
      other_deck = deck_fixture()

      assert {:ok, _} = SRS.enroll_deck(scope, deck)
      assert {:ok, _} = SRS.enroll_deck(scope, deck)

      assert SRS.enrolled?(scope, deck)
      refute SRS.enrolled?(scope, other_deck)
      refute SRS.enrolled?(other, deck)
      assert SRS.enrolled_deck_ids(scope) == MapSet.new([deck.id])
      assert SRS.enrolled_deck_ids(other) == MapSet.new()
    end

    test "can be removed" do
      scope = user_scope_fixture()
      deck = deck_fixture()
      SRS.enroll_deck(scope, deck)

      assert {:ok, 1} = SRS.unenroll_deck(scope, deck)
      assert {:ok, 0} = SRS.unenroll_deck(scope, deck)
      refute SRS.enrolled?(scope, deck)
    end

    test "anonymous visitors are enrolled in nothing" do
      assert SRS.enrolled_deck_ids(nil) == MapSet.new()
      refute SRS.enrolled?(nil, deck_fixture())
    end
  end
end
