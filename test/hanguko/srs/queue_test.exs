defmodule Hanguko.SRS.QueueTest do
  use Hanguko.DataCase, async: true

  import Hanguko.AccountsFixtures
  import Hanguko.ContentFixtures
  import Hanguko.SRSFixtures

  alias Hanguko.SRS
  alias Hanguko.SRS.Queue

  # With the default settings (UTC, 04:00 rollover) this study day runs from
  # 2026-09-11 04:00 to 2026-09-12 04:00 UTC.
  @now ~U[2026-09-11 12:00:00Z]

  setup do
    scope = user_scope_fixture()
    deck = deck_fixture(kind: :vocab, position: 1)
    SRS.enroll_deck(scope, deck)
    %{scope: scope, user: scope.user, deck: deck}
  end

  defp items(deck, n, attrs \\ []) do
    for i <- 1..n, do: item_fixture(deck, Keyword.merge([position: i, korean: "단어#{i}"], attrs))
  end

  defp queue(scope, now \\ @now, opts \\ []), do: SRS.study_queue(scope, now, opts)

  defp new_keys(queue), do: Enum.map(queue.new, &{&1.item.id, &1.template})

  describe "new cards" do
    test "come from enrolled decks in curriculum order, up to the daily limit", %{
      scope: scope,
      deck: deck
    } do
      [a, b, c | _] = items(deck, 12)
      other = deck_fixture()
      item_fixture(other)

      queue = queue(scope)
      assert length(queue.new) == 10

      assert Enum.take(new_keys(queue), 3) == [
               {a.id, :recognition},
               {b.id, :recognition},
               {c.id, :recognition}
             ]

      assert Enum.all?(queue.new, &(&1.item.deck_id == deck.id and is_nil(&1.card)))
    end

    test "respect the user's daily limit and skip retired items", %{scope: scope, deck: deck} do
      [a, b, c, d] = items(deck, 4)
      Hanguko.Repo.update!(Ecto.Changeset.change(b, retired: true))
      {:ok, _} = SRS.update_settings(scope, %{daily_new_limit: 2})

      assert new_keys(queue(scope)) == [{a.id, :recognition}, {c.id, :recognition}]
      refute d.id in Enum.map(queue(scope).new, & &1.item.id)
    end

    test "are created on first review and count against today's limit", %{
      scope: scope,
      deck: deck
    } do
      items(deck, 5)
      {:ok, _} = SRS.update_settings(scope, %{daily_new_limit: 3})

      entry = Queue.next(queue(scope))
      assert {:ok, _log} = SRS.review_card(scope, entry, 3, @now)

      queue = queue(scope, DateTime.add(@now, 1))
      assert length(queue.new) == 2
      # The reviewed card is now a learning card, due in 10 minutes.
      assert [] = queue.learning
      assert [%{item: item, template: :recognition}] = queue.learning_ahead
      assert item.id == entry.item.id
    end

    test "the new-card budget resets at the rollover hour", %{
      scope: scope,
      user: user,
      deck: deck
    } do
      [a, b, c] = items(deck, 3)
      {:ok, _} = SRS.update_settings(scope, %{daily_new_limit: 2})
      # Introduced at 03:00 UTC, before today's 04:00 rollover: yesterday.
      card_fixture(user, a,
        introduced_at: ~U[2026-09-11 03:00:00Z],
        due: ~U[2026-09-20 00:00:00Z]
      )

      card_fixture(user, b,
        introduced_at: ~U[2026-09-11 05:00:00Z],
        due: ~U[2026-09-20 00:00:00Z]
      )

      # Only b counts against today's limit, leaving one slot (c's recognition
      # card comes before a's recall card).
      assert [{c_id, :recognition}] = new_keys(queue(scope))
      assert c_id == c.id
    end

    test "introduce an item's recall card the day after its recognition card", %{
      scope: scope,
      user: user,
      deck: deck
    } do
      [a, b, c] = items(deck, 3)

      card_fixture(user, a,
        introduced_at: DateTime.add(@now, -1, :day),
        due: DateTime.add(@now, 3, :day)
      )

      card_fixture(user, b,
        introduced_at: DateTime.add(@now, -3600),
        due: DateTime.add(@now, 3, :day)
      )

      # a's recall is available (recognition introduced yesterday), b's is not
      # (introduced today); recall and recognition cards are interleaved.
      assert new_keys(queue(scope)) == [{c.id, :recognition}, {a.id, :recall}]
    end

    test "letters only have a recognition card", %{scope: scope, user: user} do
      letters = deck_fixture(kind: :hangeul, position: 1)
      SRS.enroll_deck(scope, letters)
      letter = item_fixture(letters, korean: "ㄱ", kind: :jamo)

      card_fixture(user, letter,
        introduced_at: DateTime.add(@now, -2, :day),
        due: DateTime.add(@now, 3, :day)
      )

      refute Enum.any?(queue(scope).new, &(&1.item.id == letter.id))
    end
  end

  describe "cards being studied" do
    test "due learning cards come first, then reviews due today, then new cards", %{
      scope: scope,
      user: user,
      deck: deck
    } do
      [a, b, c, d] = items(deck, 4)
      card_fixture(user, a, state: :review, due: DateTime.add(@now, 6, :hour))
      card_fixture(user, b, state: :learning, step: 1, due: DateTime.add(@now, -60))
      card_fixture(user, c, state: :review, due: ~U[2026-09-12 05:00:00Z])

      queue = queue(scope)
      assert Enum.map(queue.learning, & &1.item.id) == [b.id]
      # a is due later today; c is due after the study day ends.
      assert Enum.map(queue.review, & &1.item.id) == [a.id]
      # c isn't studied today, so its recall card can be introduced; a and b
      # are (siblings are buried).
      assert new_keys(queue) == [{d.id, :recognition}, {c.id, :recall}]
      assert Queue.next(queue).item.id == b.id
      assert Queue.counts(queue) == %{learning: 1, review: 1, new: 2}
    end

    test "learning cards are shown early when nothing else is left", %{
      scope: scope,
      user: user,
      deck: deck
    } do
      [a, b] = items(deck, 2)
      {:ok, _} = SRS.update_settings(scope, %{daily_new_limit: 0})
      card_fixture(user, a, state: :learning, step: 0, due: DateTime.add(@now, 5 * 60))
      card_fixture(user, b, state: :relearning, step: 0, due: DateTime.add(@now, 2 * 3600))

      queue = queue(scope)
      assert Queue.next(queue).item.id == a.id
      assert queue.next_learning_due == DateTime.add(@now, 2 * 3600)

      # Easy graduates a to review; b is too far off to show early.
      {:ok, _} = SRS.review_card(scope, Queue.next(queue), 4, @now)
      assert Queue.next(queue(scope)) == nil
    end

    test "reviews are limited per day, oldest first", %{scope: scope, user: user, deck: deck} do
      [a, b, c] = items(deck, 3)
      {:ok, _} = SRS.update_settings(scope, %{daily_review_limit: 2, daily_new_limit: 0})
      card_fixture(user, a, due: DateTime.add(@now, -3600))
      card_fixture(user, b, due: DateTime.add(@now, -2 * 86_400))
      card_fixture(user, c, due: DateTime.add(@now, -86_400))

      queue = queue(scope)
      assert Enum.map(queue.review, & &1.item.id) == [b.id, c.id]

      {:ok, _} = SRS.review_card(scope, Queue.next(queue), 3, @now)
      assert Enum.map(queue(scope).review, & &1.item.id) == [c.id]
    end

    test "siblings are buried: one card per item per day", %{scope: scope, user: user, deck: deck} do
      [a, b] = items(deck, 2)
      {:ok, _} = SRS.update_settings(scope, %{daily_new_limit: 0})
      card_fixture(user, a, template: :recognition, due: DateTime.add(@now, -60))
      card_fixture(user, a, template: :recall, due: DateTime.add(@now, -30))
      card_fixture(user, b, template: :recall, due: DateTime.add(@now, -10))

      b_recognition =
        card_fixture(user, b, template: :recognition, due: DateTime.add(@now, 3, :day))

      assert Enum.map(queue(scope).review, &{&1.item.id, &1.template}) ==
               [{a.id, :recognition}, {b.id, :recall}]

      # Once b's recognition card was reviewed today, its recall card waits.
      entry = %{card: b_recognition, item: b, template: :recognition}
      {:ok, _} = SRS.review_card(scope, entry, 3, DateTime.add(@now, -3600))

      assert Enum.map(queue(scope).review, &{&1.item.id, &1.template}) == [{a.id, :recognition}]
    end

    test "only enrolled decks, active items and unsuspended cards are studied", %{
      scope: scope,
      user: user,
      deck: deck
    } do
      [a, b, c] = items(deck, 3)
      other = deck_fixture()
      d = item_fixture(other)
      card_fixture(user, a, due: DateTime.add(@now, -60))
      card_fixture(user, b, due: DateTime.add(@now, -60), suspended: true)
      Hanguko.Repo.update!(Ecto.Changeset.change(c, retired: true))
      card_fixture(user, c, due: DateTime.add(@now, -60))
      card_fixture(user, d, due: DateTime.add(@now, -60))

      assert Enum.map(queue(scope).review, & &1.item.id) == [a.id]

      SRS.unenroll_deck(scope, deck)
      assert Queue.next(queue(scope)) == nil
    end

    test "can be limited to one deck", %{scope: scope, user: user, deck: deck} do
      [a] = items(deck, 1)
      other = deck_fixture(position: 2)
      SRS.enroll_deck(scope, other)
      b = item_fixture(other)
      card_fixture(user, a, due: DateTime.add(@now, -60))
      card_fixture(user, b, due: DateTime.add(@now, -60))

      assert Enum.map(queue(scope, @now, deck: other).review, & &1.item.id) == [b.id]
      assert queue(scope, @now, deck: other).new == []
    end
  end

  test "users without enrolled decks have an empty queue" do
    scope = user_scope_fixture()
    queue = SRS.study_queue(scope, @now)
    assert Queue.next(queue) == nil
    assert queue.day_start == ~U[2026-09-11 04:00:00Z]
  end
end
