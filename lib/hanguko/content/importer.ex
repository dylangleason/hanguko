defmodule Hanguko.Content.Importer do
  @moduledoc """
  Loads curated content packs (YAML) into the database.

  Each `*.yml` file under the content directory describes one deck:

      deck:
        slug: food
        title: Food
        title_ko: 음식
        kind: vocab
        level: 1
        position: 3
        description: Everyday food and drink.
      defaults:           # optional, merged into every item
        kind: word
        part_of_speech: noun
      items:
        - korean: 사과
          romanization: sagwa
          meaning: apple
        - key: bae-pear   # explicit key, for homographs or to keep an
          korean: 배       # item's identity when fixing a typo in `korean`
          meaning: pear

  A pack may also teach grammar. Each point's `examples` become sentence
  items in the pack's deck, tied to the point and blanked at `cloze`:

      grammar:
        - slug: ieyo
          title: 이에요 / 예요
          pattern: N + 이에요/예요
          explanation: |
            Markdown explaining when to use it.
          formation:
            - when: after a consonant
              form: 이에요
              example: 학생이에요
          examples:
            - korean: 저는 학생이에요.
              meaning: I am a student.
              cloze: 이에요

  A `phrases` pack is one situation. Its phrases say how polite they are,
  and may point at the same phrase at another speech level, which must be
  another item in the same pack:

      items:
        - korean: 잘 지냈어요?
          meaning: how have you been?
          metadata:
            politeness: polite     # formal | polite | casual
            context: Meeting someone you haven't seen for a while.
            literal: Did you live well?
        - korean: 잘 지냈어?
          meaning: how have you been?
          metadata:
            politeness: casual
            variant_of: 잘 지냈어요?   # stored as "<deck slug>/잘 지냈어요?"

  An item's identity is `"<deck slug>/<key>"`, where `key` defaults to its
  Korean text. Its position is its order in the file, examples last.

  Importing is idempotent and non-destructive:

    * every pack is validated before anything is written;
    * rows whose content did not change are left untouched;
    * decks and items that disappeared from the packs are marked `retired`
      instead of being deleted, so users' review history survives.
  """
  alias Ecto.Changeset
  alias Hanguko.Repo
  alias Hanguko.Content.{Deck, GrammarPoint, Item, Queries}

  @top_level_keys ~w(deck defaults items grammar)
  @deck_keys ~w(slug title title_ko kind level position description)
  @item_keys ~w(key kind korean romanization meaning part_of_speech hint notes tags metadata cloze)
  @grammar_keys ~w(slug title pattern summary level position explanation formation examples)

  @deck_defaults %{"title_ko" => nil, "description" => nil, "level" => 1, "position" => 0}
  @item_defaults %{
    "romanization" => nil,
    "part_of_speech" => nil,
    "hint" => nil,
    "notes" => nil,
    "cloze" => nil,
    "tags" => [],
    "metadata" => %{}
  }

  @empty_stats %{created: 0, updated: 0, unchanged: 0, retired: 0}

  @doc "The directory holding the app's content packs."
  def default_path, do: Application.app_dir(:hanguko, "priv/content")

  @doc """
  Imports every `*.yml` pack under `path` (recursively).

  Returns `{:ok, %{decks: stats, items: stats}}` where each `stats` map counts
  `:created`, `:updated`, `:unchanged` and `:retired` rows, or
  `{:error, messages}` with human-readable messages naming the offending
  file and item. Nothing is written when there are errors.
  """
  def import_dir(path \\ default_path()) do
    with {:ok, packs} <- load_packs(path),
         {:ok, plan} <- plan(packs) do
      apply_plan(plan)
    end
  end

  ## Loading and validating YAML

  defp load_packs(path) do
    case path |> Path.join("**/*.yml") |> Path.wildcard() |> Enum.sort() do
      [] -> {:error, ["no content packs (*.yml) found in #{path}"]}
      files -> files |> Enum.map(&load_pack(&1, path)) |> collect()
    end
  end

  defp load_pack(file, root) do
    name = Path.relative_to(file, root)

    case YamlElixir.read_from_file(file) do
      {:ok, %{"deck" => deck} = doc} when is_map(deck) ->
        defaults = Map.get(doc, "defaults") || %{}
        raw_items = Map.get(doc, "items") || []
        raw_grammar = Map.get(doc, "grammar") || []

        # Anything that isn't shaped like a pack is reported on its own:
        # there is nothing to walk through afterwards.
        case shape_errors(name, raw_items, raw_grammar) do
          [] ->
            errors =
              unknown_keys(doc, @top_level_keys, name) ++
                unknown_keys(deck, @deck_keys, "#{name}: deck") ++
                unknown_keys(defaults, @item_keys, "#{name}: defaults")

            deck_attrs = @deck_defaults |> Map.merge(deck) |> Map.put("retired", false)
            slug = to_string(deck["slug"])

            items =
              raw_items
              |> Enum.with_index(1)
              |> Enum.map(fn {raw, i} ->
                build_item(raw, i, "#{name}: item #{i}", defaults, slug)
              end)

            grammar =
              build_grammar(raw_grammar, defaults, slug, name, length(items), deck_attrs["level"])

            item_errors =
              Enum.flat_map(items, &elem(&1, 2)) ++
                variant_errors(items ++ Enum.flat_map(grammar, & &1.examples), slug) ++
                Enum.flat_map(grammar, fn point ->
                  point.errors ++ Enum.flat_map(point.examples, &elem(&1, 2))
                end)

            case errors ++ item_errors do
              [] ->
                {:ok, %{file: name, slug: slug, deck: deck_attrs, items: items, grammar: grammar}}

              errors ->
                {:error, errors}
            end

          errors ->
            {:error, errors}
        end

      {:ok, _} ->
        {:error, ["#{name}: expected a top-level `deck` map"]}

      {:error, %YamlElixir.ParsingError{line: line, column: column, message: message}}
      when is_integer(line) ->
        {:error, ["#{name}:#{line}:#{column}: invalid YAML: #{message}"]}

      {:error, %{message: message}} ->
        {:error, ["#{name}: invalid YAML: #{message}"]}
    end
  end

  defp build_item(raw, position, what, defaults, slug) when is_map(raw) do
    attrs = @item_defaults |> Map.merge(defaults) |> Map.merge(raw)
    key = attrs["key"] || attrs["korean"]
    source_key = if key, do: "#{slug}/#{key}", else: "#{slug}/##{position}"
    label = "#{what} (#{key || "no key"})"

    attrs =
      attrs
      |> Map.delete("key")
      |> Map.merge(%{"source_key" => source_key, "position" => position, "retired" => false})
      |> qualify_variant(slug)

    {label, attrs, unknown_keys(raw, @item_keys, label)}
  end

  defp build_item(_raw, _position, what, _defaults, _slug),
    do: {nil, nil, ["#{what} must be a map"]}

  # A pack names a variant by the other item's key; it is stored as that
  # item's full source key, so it stays unambiguous across decks.
  defp qualify_variant(%{"metadata" => %{"variant_of" => key} = metadata} = attrs, slug)
       when is_binary(key) or is_integer(key) do
    %{attrs | "metadata" => %{metadata | "variant_of" => "#{slug}/#{key}"}}
  end

  defp qualify_variant(attrs, _slug), do: attrs

  # Variants are shown next to each other, so each must name a different
  # item in the same pack: one of its plain items or grammar examples. A
  # pair is linked from one side only; linked from both, each form would be
  # listed twice.
  defp variant_errors(items, slug) do
    keys = for {_label, %{"source_key" => key}, _errors} <- items, into: MapSet.new(), do: key

    order =
      for {{_label, %{"source_key" => key}, _errors}, index} <- Enum.with_index(items),
          into: %{},
          do: {key, index}

    targets =
      for {_label, %{"source_key" => key, "metadata" => %{"variant_of" => target}}, _errors} <-
            items,
          into: %{},
          do: {key, target}

    Enum.flat_map(items, fn
      {label, %{"source_key" => key, "metadata" => %{"variant_of" => target}}, _errors}
      when is_binary(target) ->
        cond do
          target == key ->
            ["#{label}: variant_of can't point at the item itself"]

          # Reported once, on the later item of the pair.
          targets[target] == key and order[target] < order[key] ->
            other = String.replace_prefix(target, slug <> "/", "")

            [
              "#{label}: variant_of #{inspect(other)} already names this item as its variant; " <>
                "link the pair from one side only"
            ]

          MapSet.member?(keys, target) ->
            []

          true ->
            key = String.replace_prefix(target, slug <> "/", "")
            ["#{label}: variant_of #{inspect(key)} is not an item in this deck"]
        end

      {label, %{"metadata" => %{"variant_of" => target}}, _errors} when not is_nil(target) ->
        ["#{label}: variant_of must be the key of another item"]

      _ ->
        []
    end)
  end

  defp shape_errors(file, items, grammar) do
    cond do
      not is_list(items) -> ["#{file}: `items` must be a list"]
      not is_list(grammar) -> ["#{file}: `grammar` must be a list"]
      items == [] and grammar == [] -> ["#{file}: needs `items`, `grammar`, or both"]
      true -> []
    end
  end

  # Each grammar point becomes a lesson plus, from its `examples`, sentence
  # items in the same deck. Their positions continue after the plain items.
  defp build_grammar(raw_grammar, defaults, slug, file, item_count, deck_level) do
    {points, _} =
      Enum.map_reduce(Enum.with_index(raw_grammar, 1), item_count, fn {raw, index}, position ->
        build_point(raw, index, position, defaults, slug, file, deck_level)
      end)

    points
  end

  defp build_point(raw, index, position, defaults, slug, file, deck_level) when is_map(raw) do
    label = "#{file}: grammar #{index} (#{raw["slug"] || "no slug"})"
    examples = List.wrap(raw["examples"])

    attrs =
      raw
      |> Map.delete("examples")
      |> Map.put("retired", false)
      # A point sits at its deck's level, in file order, unless it says
      # otherwise.
      |> Map.put_new("level", deck_level)
      |> Map.put_new("position", index)

    built =
      examples
      |> Enum.with_index(1)
      |> Enum.map(fn {example, i} ->
        example = if is_map(example), do: Map.put_new(example, "kind", "sentence"), else: example
        build_item(example, position + i, "#{label} example #{i}", defaults, slug)
      end)

    errors =
      unknown_keys(raw, @grammar_keys, label) ++
        if examples == [], do: ["#{label}: needs at least one example"], else: []

    point = %{
      label: label,
      slug: to_string(raw["slug"]),
      attrs: attrs,
      examples: built,
      errors: errors
    }

    {point, position + length(examples)}
  end

  defp build_point(_raw, index, position, _defaults, _slug, file, _deck_level) do
    point = %{
      label: nil,
      slug: nil,
      attrs: nil,
      examples: [],
      errors: ["#{file}: grammar #{index} must be a map"]
    }

    {point, position}
  end

  defp unknown_keys(map, allowed, label) do
    case Map.keys(map) -- allowed do
      [] -> []
      keys -> ["#{label}: unknown keys #{Enum.join(keys, ", ")}"]
    end
  end

  ## Planning: diff the packs against the database

  defp plan(packs) do
    existing_decks = Deck |> Repo.all() |> Map.new(&{&1.slug, &1})
    existing_items = Item |> Repo.all() |> Map.new(&{&1.source_key, &1})
    existing_points = GrammarPoint |> Repo.all() |> Map.new(&{&1.slug, &1})

    item_changesets = fn built ->
      for {label, attrs, []} <- built do
        {label, Item.import_changeset(existing_items[attrs["source_key"]] || %Item{}, attrs)}
      end
    end

    planned =
      Enum.map(packs, fn pack ->
        deck = Deck.import_changeset(existing_decks[pack.slug] || %Deck{}, pack.deck)

        grammar =
          for point <- pack.grammar, point.attrs do
            existing = existing_points[point.slug] || %GrammarPoint{}

            %{
              label: point.label,
              slug: point.slug,
              point: GrammarPoint.import_changeset(existing, point.attrs),
              examples: item_changesets.(point.examples)
            }
          end

        %{
          file: pack.file,
          slug: pack.slug,
          deck: deck,
          items: item_changesets.(pack.items),
          grammar: grammar
        }
      end)

    errors =
      duplicates(Enum.map(packs, & &1.slug), "deck slug") ++
        duplicates(for(pack <- packs, point <- pack.grammar, do: point.slug), "grammar slug") ++
        duplicates(all_source_keys(packs), "item key") ++
        Enum.flat_map(planned, fn pack ->
          changeset_errors(pack.deck, "#{pack.file}: deck") ++
            Enum.flat_map(pack.items, fn {label, cs} -> changeset_errors(cs, label) end) ++
            Enum.flat_map(pack.grammar, fn point ->
              changeset_errors(point.point, point.label) ++
                Enum.flat_map(point.examples, fn {label, cs} -> changeset_errors(cs, label) end)
            end)
        end)

    case errors do
      [] -> {:ok, planned}
      errors -> {:error, errors}
    end
  end

  defp all_source_keys(packs) do
    for pack <- packs,
        built <- [pack.items | Enum.map(pack.grammar, & &1.examples)],
        {_label, attrs, _errors} <- built,
        do: attrs["source_key"]
  end

  defp duplicates(values, what) do
    values
    |> Enum.frequencies()
    |> Enum.filter(fn {_, count} -> count > 1 end)
    |> Enum.map(fn {value, _} ->
      "duplicate #{what} #{inspect(value)} (add an explicit `key` to one of them)"
    end)
  end

  defp changeset_errors(%Changeset{valid?: true}, _label), do: []

  defp changeset_errors(changeset, label) do
    changeset
    |> Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", fn _ -> format_value(value) end)
      end)
    end)
    |> Enum.map(fn {field, messages} -> "#{label}: #{field} #{Enum.join(messages, ", ")}" end)
  end

  defp format_value(value) when is_binary(value) or is_number(value) or is_atom(value),
    do: to_string(value)

  defp format_value(value), do: inspect(value)

  ## Applying

  defp apply_plan(planned) do
    Repo.transact(fn ->
      empty = %{decks: @empty_stats, items: @empty_stats, grammar_points: @empty_stats}

      stats =
        Enum.reduce(planned, empty, fn pack, stats ->
          {deck_result, deck} = save(pack.deck)
          stats = bump(stats, :decks, deck_result)

          stats =
            Enum.reduce(pack.items, stats, fn {_label, cs}, stats ->
              {item_result, _item} =
                cs
                |> Changeset.put_change(:deck_id, deck.id)
                # An item outside a `grammar:` block belongs to no point,
                # even if it was one of its examples before.
                |> Changeset.put_change(:grammar_point_id, nil)
                |> save()

              bump(stats, :items, item_result)
            end)

          Enum.reduce(pack.grammar, stats, fn point, stats ->
            {point_result, saved} = save(Changeset.put_change(point.point, :deck_id, deck.id))
            stats = bump(stats, :grammar_points, point_result)

            Enum.reduce(point.examples, stats, fn {_label, cs}, stats ->
              {item_result, _item} =
                cs
                |> Changeset.put_change(:deck_id, deck.id)
                |> Changeset.put_change(:grammar_point_id, saved.id)
                |> save()

              bump(stats, :items, item_result)
            end)
          end)
        end)

      slugs = Enum.map(planned, & &1.slug)
      point_slugs = for pack <- planned, point <- pack.grammar, do: point.slug

      keys =
        for pack <- planned,
            changesets <- [pack.items | Enum.map(pack.grammar, & &1.examples)],
            {_label, cs} <- changesets,
            do: Changeset.get_field(cs, :source_key)

      now = DateTime.utc_now(:second)

      retire = [set: [retired: true, updated_at: now]]
      {retired_decks, _} = Repo.update_all(Queries.missing_decks(slugs), retire)
      {retired_items, _} = Repo.update_all(Queries.missing_items(keys), retire)
      {retired_points, _} = Repo.update_all(Queries.missing_grammar_points(point_slugs), retire)

      {:ok,
       stats
       |> put_in([:decks, :retired], retired_decks)
       |> put_in([:items, :retired], retired_items)
       |> put_in([:grammar_points, :retired], retired_points)}
    end)
  end

  defp save(%Changeset{data: %{__meta__: %{state: :built}}} = cs),
    do: {:created, Repo.insert!(cs)}

  defp save(%Changeset{changes: changes} = cs) when map_size(changes) == 0,
    do: {:unchanged, cs.data}

  defp save(cs), do: {:updated, Repo.update!(cs)}

  defp bump(stats, table, result), do: update_in(stats, [table, result], &(&1 + 1))

  defp collect(results) do
    case Enum.flat_map(results, fn
           {:error, errors} -> errors
           {:ok, _} -> []
         end) do
      [] -> {:ok, Enum.map(results, fn {:ok, value} -> value end)}
      errors -> {:error, errors}
    end
  end
end
