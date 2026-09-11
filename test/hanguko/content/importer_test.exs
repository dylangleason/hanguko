defmodule Hanguko.Content.ImporterTest do
  use Hanguko.DataCase, async: true

  alias Hanguko.Content.{Deck, Importer, Item}

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

  @tag :tmp_dir
  test "fails when there are no packs", %{tmp_dir: dir} do
    assert {:error, [error]} = Importer.import_dir(dir)
    assert error =~ "no content packs"
  end
end
