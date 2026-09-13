defmodule Hanguko.Content.ImporterTest do
  use Hanguko.DataCase, async: true

  alias Hanguko.Content.{Deck, GrammarPoint, Importer, Item}

  @food """
  deck:
    slug: food
    title: Food
    title_ko: 음식
    kind: vocab
    position: 1
  defaults:
    kind: word
    part_of_speech: noun
  items:
    - korean: 사과
      romanization: sagwa
      meaning: apple
    - korean: 물
      romanization: mul
      meaning: water
      tags: [drinks]
    - key: bae-pear
      korean: 배
      meaning: pear
  """

  @greetings """
  deck:
    slug: greetings
    title: Greetings
    kind: phrases
  items:
    - korean: 안녕하세요
      kind: phrase
      meaning: hello
      metadata:
        politeness: polite
  """

  @grammar """
  deck:
    slug: grammar-basics
    title: Sentence basics
    kind: sentences
  items:
    - kind: sentence
      korean: 안녕히 계세요.
      meaning: Goodbye.
  grammar:
    - slug: want-go-sipda
      title: -고 싶다
      pattern: 동사 어간 + 고 싶어요
      summary: Saying what you want to do.
      explanation: |
        Attach **-고 싶어요** to a verb stem.
      formation:
        - when: Any verb stem
          form: -고 싶어요
          example: 먹다 → 먹고 싶어요
      examples:
        - korean: 한국에 가고 싶어요.
          meaning: I want to go to Korea.
          cloze: 고 싶어요
        - korean: 김치찌개를 먹고 싶어요.
          meaning: I want to eat kimchi stew.
          cloze: 고 싶어요
  """

  defp write_packs(dir, packs) do
    for {name, yaml} <- packs do
      path = Path.join(dir, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, yaml)
    end

    dir
  end

  defp items_by_key, do: Item |> Repo.all() |> Map.new(&{&1.source_key, &1})

  @tag :tmp_dir
  test "imports decks and items, applying defaults and file order", %{tmp_dir: dir} do
    write_packs(dir, %{"vocab/food.yml" => @food, "greetings.yml" => @greetings})

    assert {:ok, stats} = Importer.import_dir(dir)
    assert stats.decks == %{created: 2, updated: 0, unchanged: 0, retired: 0}
    assert stats.items == %{created: 4, updated: 0, unchanged: 0, retired: 0}

    items = items_by_key()
    apple = items["food/사과"]
    assert apple.kind == :word
    assert apple.part_of_speech == "noun"
    assert apple.position == 1
    assert items["food/물"].tags == ["drinks"]
    assert items["food/bae-pear"].korean == "배"
    assert items["greetings/안녕하세요"].metadata == %{"politeness" => "polite"}

    food = Repo.get_by!(Deck, slug: "food")
    assert food.title_ko == "음식"
    assert food.level == 1
    assert apple.deck_id == food.id
  end

  @tag :tmp_dir
  test "re-importing unchanged packs writes nothing", %{tmp_dir: dir} do
    write_packs(dir, %{"food.yml" => @food})
    assert {:ok, _} = Importer.import_dir(dir)
    before = Repo.all(Item)

    assert {:ok, stats} = Importer.import_dir(dir)
    assert stats.decks == %{created: 0, updated: 0, unchanged: 1, retired: 0}
    assert stats.items == %{created: 0, updated: 0, unchanged: 3, retired: 0}
    assert Repo.all(Item) == before
  end

  @tag :tmp_dir
  test "updates changed items and retires removed ones, keeping their ids", %{tmp_dir: dir} do
    write_packs(dir, %{"food.yml" => @food, "greetings.yml" => @greetings})
    {:ok, _} = Importer.import_dir(dir)
    %{"food/사과" => apple, "food/물" => water} = items_by_key()

    File.rm!(Path.join(dir, "greetings.yml"))

    File.write!(
      Path.join(dir, "food.yml"),
      @food
      |> String.replace("meaning: apple", "meaning: apple; apples")
      |> String.replace("  - key: bae-pear\n    korean: 배\n    meaning: pear\n", "")
    )

    assert {:ok, stats} = Importer.import_dir(dir)
    assert stats.decks == %{created: 0, updated: 0, unchanged: 1, retired: 1}
    assert stats.items == %{created: 0, updated: 1, unchanged: 1, retired: 2}

    items = items_by_key()
    assert items["food/사과"].id == apple.id
    assert items["food/사과"].meaning == "apple; apples"
    assert items["food/물"] == water
    assert items["food/bae-pear"].retired
    assert items["greetings/안녕하세요"].retired
    assert Repo.get_by!(Deck, slug: "greetings").retired
  end

  @tag :tmp_dir
  test "restores retired items when they come back", %{tmp_dir: dir} do
    write_packs(dir, %{"food.yml" => @food})
    {:ok, _} = Importer.import_dir(dir)
    File.write!(Path.join(dir, "food.yml"), String.replace(@food, "- korean: 물", "- korean: 우유"))
    {:ok, _} = Importer.import_dir(dir)
    assert items_by_key()["food/물"].retired

    File.write!(Path.join(dir, "food.yml"), @food)
    assert {:ok, %{items: %{updated: 1}}} = Importer.import_dir(dir)
    refute items_by_key()["food/물"].retired
  end

  @tag :tmp_dir
  test "treats empty tags and metadata as none", %{tmp_dir: dir} do
    write_packs(dir, %{
      "letters.yml" => """
      deck: {slug: letters, title: Letters, kind: hangeul}
      defaults:
        kind: jamo
        tags: [consonant]
        metadata: {name: default}
      items:
        - korean: ㄱ
          meaning: g
          tags:
          metadata:
      """
    })

    assert {:ok, _} = Importer.import_dir(dir)
    assert %{tags: [], metadata: %{}} = items_by_key()["letters/ㄱ"]
    assert {:ok, %{items: %{unchanged: 1}}} = Importer.import_dir(dir)
  end

  @tag :tmp_dir
  test "imports text longer than 255 characters", %{tmp_dir: dir} do
    sentence = String.duplicate("저는 매일 아침에 커피를 마셔요. ", 20)
    meaning = String.duplicate("I drink coffee every morning. ", 20)
    assert String.length(sentence) > 255 and String.length(meaning) > 255

    write_packs(dir, %{
      "sentences.yml" => """
      deck: {slug: sentences, title: Sentences, kind: sentences}
      items:
        - kind: sentence
          korean: "#{sentence}"
          meaning: "#{meaning}"
      """
    })

    assert {:ok, %{items: %{created: 1}}} = Importer.import_dir(dir)
    assert %{korean: ^sentence, meaning: ^meaning} = items_by_key()["sentences/#{sentence}"]
  end

  @tag :tmp_dir
  test "imports grammar points with their example sentences", %{tmp_dir: dir} do
    write_packs(dir, %{"grammar.yml" => @grammar})

    assert {:ok, stats} = Importer.import_dir(dir)
    assert stats.grammar_points == %{created: 1, updated: 0, unchanged: 0, retired: 0}
    assert stats.items == %{created: 3, updated: 0, unchanged: 0, retired: 0}

    point = Repo.get_by!(GrammarPoint, slug: "want-go-sipda")
    assert point.title == "-고 싶다"
    assert point.explanation =~ "**-고 싶어요**"
    assert [%{"when" => "Any verb stem", "form" => "-고 싶어요"}] = point.formation

    items = items_by_key()
    example = items["grammar-basics/한국에 가고 싶어요."]
    assert example.kind == :sentence
    assert example.cloze == "고 싶어요"
    assert example.grammar_point_id == point.id
    # Examples are numbered after the pack's own items.
    assert items["grammar-basics/안녕히 계세요."].position == 1
    assert example.position == 2
    assert is_nil(items["grammar-basics/안녕히 계세요."].grammar_point_id)

    assert {:ok, %{grammar_points: %{unchanged: 1}, items: %{unchanged: 3}}} =
             Importer.import_dir(dir)
  end

  @tag :tmp_dir
  test "retires grammar points that leave the packs", %{tmp_dir: dir} do
    write_packs(dir, %{"grammar.yml" => @grammar})
    {:ok, _} = Importer.import_dir(dir)
    point = Repo.get_by!(GrammarPoint, slug: "want-go-sipda")

    write_packs(dir, %{"grammar.yml" => @food})
    assert {:ok, %{grammar_points: %{retired: 1}}} = Importer.import_dir(dir)

    reloaded = Repo.get!(GrammarPoint, point.id)
    assert reloaded.retired
    # The sentences keep pointing at it, so users' cards survive.
    assert items_by_key()["grammar-basics/한국에 가고 싶어요."].grammar_point_id == point.id
  end

  @tag :tmp_dir
  test "an example moved out of a grammar point stops being one", %{tmp_dir: dir} do
    write_packs(dir, %{"grammar.yml" => @grammar})
    {:ok, _} = Importer.import_dir(dir)
    assert items_by_key()["grammar-basics/한국에 가고 싶어요."].grammar_point_id

    # The same sentence, now a plain item of the deck.
    write_packs(dir, %{
      "grammar.yml" => """
      deck: {slug: grammar-basics, title: Sentence basics, kind: sentences}
      items:
        - kind: sentence
          korean: 한국에 가고 싶어요.
          meaning: I want to go to Korea.
      """
    })

    assert {:ok, _} = Importer.import_dir(dir)
    item = items_by_key()["grammar-basics/한국에 가고 싶어요."]
    assert is_nil(item.grammar_point_id)
    assert is_nil(item.cloze)
    refute item.retired
  end

  @tag :tmp_dir
  test "a grammar point keeps the position its pack gives it", %{tmp_dir: dir} do
    write_packs(dir, %{
      "grammar.yml" =>
        String.replace(
          @grammar,
          "  - slug: want-go-sipda",
          "  - slug: want-go-sipda\n    position: 7\n    level: 3"
        )
    })

    assert {:ok, _} = Importer.import_dir(dir)
    point = Repo.get_by!(GrammarPoint, slug: "want-go-sipda")
    assert point.position == 7
    assert point.level == 3
  end

  @tag :tmp_dir
  test "reports a pack whose items aren't a list", %{tmp_dir: dir} do
    write_packs(dir, %{
      "bad.yml" => """
      deck: {slug: bad, title: Bad, kind: vocab}
      items: 사과
      """
    })

    assert {:error, ["bad.yml: `items` must be a list"]} = Importer.import_dir(dir)
  end

  @tag :tmp_dir
  test "rejects a cloze that isn't in its sentence", %{tmp_dir: dir} do
    write_packs(dir, %{
      "grammar.yml" => String.replace(@grammar, "cloze: 고 싶어요\n", "cloze: 고 있어요\n", global: false)
    })

    assert {:error, errors} = Importer.import_dir(dir)

    assert ("grammar.yml: grammar 1 (want-go-sipda) example 1 (한국에 가고 싶어요.): " <>
              "cloze \"고 있어요\" does not appear in \"한국에 가고 싶어요.\"") in errors

    assert Repo.aggregate(GrammarPoint, :count) == 0
  end

  @tag :tmp_dir
  test "rejects a grammar point with no examples", %{tmp_dir: dir} do
    write_packs(dir, %{
      "empty.yml" => """
      deck: {slug: empty, title: Empty, kind: sentences}
      grammar:
        - slug: no-examples
          title: -지만
          pattern: 어간 + 지만
          explanation: But.
      """
    })

    assert {:error, errors} = Importer.import_dir(dir)
    assert "empty.yml: grammar 1 (no-examples): needs at least one example" in errors
    assert Repo.aggregate(GrammarPoint, :count) == 0
  end

  @tag :tmp_dir
  test "reports every error with its file and writes nothing", %{tmp_dir: dir} do
    write_packs(dir, %{
      "good.yml" => @food,
      "bad.yml" => """
      deck:
        slug: Bad Slug
        title: Bad
        kind: vocab
      items:
        - korean: hello
          meaning: not korean
          kind: word
        - korean: 좋다
          kind: word
          meanng: good
      """
    })

    assert {:error, errors} = Importer.import_dir(dir)
    assert "bad.yml: item 2 (좋다): unknown keys meanng" in errors
    assert Repo.aggregate(Deck, :count) == 0

    File.write!(
      Path.join(dir, "bad.yml"),
      String.replace(File.read!(Path.join(dir, "bad.yml")), "meanng", "meaning")
    )

    assert {:error, errors} = Importer.import_dir(dir)
    assert "bad.yml: deck: slug must be lowercase words separated by dashes" in errors
    assert "bad.yml: item 1 (hello): korean must contain Hangul" in errors
    assert Repo.aggregate(Deck, :count) == 0
  end

  @tag :tmp_dir
  test "rejects duplicate keys and malformed YAML", %{tmp_dir: dir} do
    write_packs(dir, %{
      "dupes.yml" => """
      deck: {slug: dupes, title: Dupes, kind: vocab}
      items:
        - {korean: 배, meaning: pear, kind: word}
        - {korean: 배, meaning: boat, kind: word}
      """,
      "broken.yml" => "deck: [unclosed"
    })

    assert {:error, errors} = Importer.import_dir(dir)
    assert Enum.any?(errors, &String.starts_with?(&1, "broken.yml:"))

    File.rm!(Path.join(dir, "broken.yml"))
    assert {:error, [error]} = Importer.import_dir(dir)
    assert error =~ ~s(duplicate item key "dupes/배")
  end

  @variants """
  deck:
    slug: greetings
    title: Greetings
    kind: phrases
  defaults:
    kind: phrase
  items:
    - korean: 잘 지냈어요?
      meaning: how have you been?
      metadata:
        politeness: polite
    - korean: 잘 지냈어?
      meaning: how have you been?
      metadata:
        politeness: casual
        variant_of: 잘 지냈어요?
  """

  @tag :tmp_dir
  test "links a phrase to its variant by the variant's full key", %{tmp_dir: dir} do
    write_packs(dir, %{"greetings.yml" => @variants})

    assert {:ok, _} = Importer.import_dir(dir)
    casual = items_by_key()["greetings/잘 지냈어?"]
    assert casual.metadata["variant_of"] == "greetings/잘 지냈어요?"

    assert {:ok, %{items: %{created: 0, updated: 0, unchanged: 2}}} = Importer.import_dir(dir)
  end

  @tag :tmp_dir
  test "rejects a variant that isn't another item in the deck", %{tmp_dir: dir} do
    write_packs(dir, %{
      "greetings.yml" => """
      deck:
        slug: greetings
        title: Greetings
        kind: phrases
      defaults:
        kind: phrase
      items:
        - korean: 안녕
          meaning: hi
          metadata:
            variant_of: 안녕하세요
        - korean: 잘 자
          meaning: good night
          metadata:
            variant_of: 잘 자
      """
    })

    assert {:error, errors} = Importer.import_dir(dir)

    assert ~s[greetings.yml: item 1 (안녕): variant_of "안녕하세요" is not an item in this deck] in errors

    assert "greetings.yml: item 2 (잘 자): variant_of can't point at the item itself" in errors
    assert Repo.aggregate(Item, :count) == 0
  end

  @tag :tmp_dir
  test "rejects a speech level that doesn't exist", %{tmp_dir: dir} do
    write_packs(dir, %{"greetings.yml" => String.replace(@variants, "casual", "informal")})

    assert {:error, errors} = Importer.import_dir(dir)

    assert ~s[greetings.yml: item 2 (잘 지냈어?): metadata politeness "informal" is not one of formal, polite, casual] in errors
  end

  @tag :tmp_dir
  test "fails when there are no packs", %{tmp_dir: dir} do
    assert {:error, [error]} = Importer.import_dir(dir)
    assert error =~ "no content packs"
  end
end
