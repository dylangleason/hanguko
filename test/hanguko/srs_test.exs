defmodule Hanguko.SRSTest do
  use Hanguko.DataCase, async: true

  import Hanguko.AccountsFixtures
  import Hanguko.ContentFixtures
  import Hanguko.SRSFixtures

  alias Hanguko.SRS
  alias Hanguko.SRS.{Card, ReviewLog, Settings}

  @now ~U[2026-09-11 12:00:00Z]

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

  describe "settings" do
    test "default until saved, then validated" do
      scope = user_scope_fixture()
      assert %Settings{id: nil, daily_new_limit: 10, timezone: nil} = SRS.get_settings(scope)

      assert {:ok, %Settings{daily_new_limit: 20}} =
               SRS.update_settings(scope, %{daily_new_limit: 20})

      assert %Settings{daily_new_limit: 20} = SRS.get_settings(scope)

      assert {:error, changeset} =
               SRS.update_settings(scope, %{
                 daily_new_limit: -1,
                 desired_retention: 0.5,
                 timezone: "Mars/Olympus"
               })

      assert %{
               daily_new_limit: [_],
               desired_retention: [_],
               timezone: ["is not a known time zone"]
             } =
               errors_on(changeset)
    end

    test "the browser's time zone is stored once" do
      scope = user_scope_fixture()

      assert %Settings{timezone: nil} = SRS.put_detected_timezone(scope, "Not/AZone")
      assert %Settings{timezone: "Asia/Seoul"} = SRS.put_detected_timezone(scope, "Asia/Seoul")
      assert %Settings{timezone: "Asia/Seoul"} = SRS.put_detected_timezone(scope, "Europe/Paris")
    end
  end

  describe "reviewing" do
    setup do
      scope = user_scope_fixture()
      deck = deck_fixture()
      SRS.enroll_deck(scope, deck)
      item = item_fixture(deck)
      %{scope: scope, item: item, entry: %{card: nil, item: item, template: :recognition}}
    end

    test "a new card is created on its first review", %{scope: scope, item: item, entry: entry} do
      assert {:ok, log} = SRS.review_card(scope, entry, 3, @now, duration_ms: 4200)

      card = Repo.get!(Card, log.card_id)
      assert %Card{item_id: item_id, template: :recognition, state: :learning, reps: 1} = card
      assert item_id == item.id
      assert card.introduced_at == @now
      assert card.due == DateTime.add(@now, 600)

      assert %ReviewLog{rating: 3, state_before: nil, state_after: :learning, duration_ms: 4200} =
               log

      assert log.scheduled_seconds == 600
      assert ReviewLog.first_review?(log)
    end

    test "reviewing the same new card twice is rejected", %{scope: scope, entry: entry} do
      assert {:ok, _} = SRS.review_card(scope, entry, 3, @now)
      assert {:error, :stale} = SRS.review_card(scope, entry, 3, @now)
    end

    test "a forgotten review card lapses", %{scope: scope, item: item} do
      card =
        card_fixture(scope.user, item, due: @now, last_review_at: DateTime.add(@now, -5, :day))

      assert {:ok, log} =
               SRS.review_card(scope, %{card: card, item: item, template: :recognition}, 1, @now)

      assert log.state_before == :review
      assert log.elapsed_days == 5
      assert %Card{state: :relearning, lapses: 1, reps: 4} = Repo.get!(Card, card.id)
    end

    test "reviews are scheduled from the card's latest state", %{scope: scope, item: item} do
      card = card_fixture(scope.user, item, state: :learning, step: 0, due: @now)
      stale_entry = %{card: card, item: item, template: :recognition}

      {:ok, _} = SRS.review_card(scope, stale_entry, 3, @now)
      {:ok, log} = SRS.review_card(scope, stale_entry, 3, DateTime.add(@now, 600))

      assert log.step_before == 1
      assert %Card{state: :review, reps: 5} = Repo.get!(Card, card.id)
    end

    test "cards of other users can't be reviewed", %{item: item} do
      other = user_scope_fixture()
      card = card_fixture(user_fixture(), item)

      assert {:error, :stale} =
               SRS.review_card(other, %{card: card, item: item, template: :recognition}, 3, @now)
    end
  end

  describe "undo" do
    setup do
      scope = user_scope_fixture()
      deck = deck_fixture()
      SRS.enroll_deck(scope, deck)
      %{scope: scope, item: item_fixture(deck)}
    end

    test "undoing a first review deletes the card", %{scope: scope, item: item} do
      entry = %{card: nil, item: item, template: :recognition}
      {:ok, log} = SRS.review_card(scope, entry, 3, @now)

      assert {:ok, %{card: nil, item: undone_item, template: :recognition}} =
               SRS.undo_review(scope, log)

      assert undone_item.id == item.id
      refute Repo.get(Card, log.card_id)
      refute Repo.get(ReviewLog, log.id)
    end

    test "undoing a review restores the card", %{scope: scope, item: item} do
      card = card_fixture(scope.user, item, due: @now)

      {:ok, log} =
        SRS.review_card(scope, %{card: card, item: item, template: :recognition}, 1, @now)

      assert {:ok, %{card: restored}} = SRS.undo_review(scope, log)

      assert Map.take(restored, [
               :state,
               :step,
               :stability,
               :difficulty,
               :due,
               :last_review_at,
               :reps,
               :lapses
             ]) ==
               Map.take(card, [
                 :state,
                 :step,
                 :stability,
                 :difficulty,
                 :due,
                 :last_review_at,
                 :reps,
                 :lapses
               ])

      refute Repo.get(ReviewLog, log.id)
    end

    test "only the latest review of a card, by its owner, can be undone", %{
      scope: scope,
      item: item
    } do
      card = card_fixture(scope.user, item, state: :learning, step: 0, due: @now)
      entry = %{card: card, item: item, template: :recognition}
      {:ok, first} = SRS.review_card(scope, entry, 3, @now)
      {:ok, second} = SRS.review_card(scope, entry, 3, DateTime.add(@now, 600))

      assert {:error, :not_latest} = SRS.undo_review(scope, first)
      assert {:error, :not_found} = SRS.undo_review(user_scope_fixture(), second)
      assert {:ok, _} = SRS.undo_review(scope, second)
      assert {:ok, _} = SRS.undo_review(scope, first)
    end
  end

  test "summary counts today's work per enrolled deck" do
    scope = user_scope_fixture()
    food = deck_fixture(position: 1)
    places = deck_fixture(position: 2)
    SRS.enroll_deck(scope, food)
    SRS.enroll_deck(scope, places)
    apple = item_fixture(food, position: 1)
    item_fixture(food, position: 2)
    item_fixture(places, position: 1)
    card_fixture(scope.user, apple, due: DateTime.add(@now, -60))

    {:ok, _} =
      SRS.review_card(
        scope,
        %{card: nil, item: item_fixture(deck_fixture()), template: :recognition},
        3,
        @now
      )

    summary = SRS.summary(scope, @now)

    assert [%{deck: %{id: food_id}, due: 1, new: 1}, %{deck: %{id: places_id}, due: 0, new: 1}] =
             summary.decks

    assert {food_id, places_id} == {food.id, places.id}
    assert %{due: 1, new: 2, reviewed_today: 1, next_learning_due: nil} = summary
  end
end
