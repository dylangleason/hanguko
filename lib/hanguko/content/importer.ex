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

  An item's identity is `"<deck slug>/<key>"`, where `key` defaults to its
  Korean text. Its position is its order in the file.

  Importing is idempotent and non-destructive:

    * every pack is validated before anything is written;
    * rows whose content did not change are left untouched;
    * decks and items that disappeared from the packs are marked `retired`
      instead of being deleted, so users' review history survives.
  """
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Hanguko.Repo
  alias Hanguko.Content.{Deck, Item}

  @top_level_keys ~w(deck defaults items)
  @deck_keys ~w(slug title title_ko kind level position description)
  @item_keys ~w(key kind korean romanization meaning part_of_speech hint notes tags metadata)

  @deck_defaults %{"title_ko" => nil, "description" => nil, "level" => 1, "position" => 0}
  @item_defaults %{
    "romanization" => nil,
    "part_of_speech" => nil,
    "hint" => nil,
    "notes" => nil,
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
      {:ok, %{"deck" => deck, "items" => items} = doc} when is_map(deck) and is_list(items) ->
        defaults = Map.get(doc, "defaults") || %{}

        errors =
          unknown_keys(doc, @top_level_keys, name) ++
            unknown_keys(deck, @deck_keys, "#{name}: deck") ++
            unknown_keys(defaults, @item_keys, "#{name}: defaults")

        deck_attrs = @deck_defaults |> Map.merge(deck) |> Map.put("retired", false)
        slug = to_string(deck["slug"])
        items = items |> Enum.with_index(1) |> Enum.map(&build_item(&1, defaults, slug, name))

        case errors ++ Enum.flat_map(items, &elem(&1, 2)) do
          [] -> {:ok, %{file: name, slug: slug, deck: deck_attrs, items: items}}
          errors -> {:error, errors}
        end

      {:ok, _} ->
        {:error, ["#{name}: expected a top-level `deck` map and an `items` list"]}

      {:error, %YamlElixir.ParsingError{line: line, column: column, message: message}}
      when is_integer(line) ->
        {:error, ["#{name}:#{line}:#{column}: invalid YAML: #{message}"]}

      {:error, %{message: message}} ->
        {:error, ["#{name}: invalid YAML: #{message}"]}
    end
  end

  defp build_item({raw, index}, defaults, slug, file) when is_map(raw) do
    attrs = @item_defaults |> Map.merge(defaults) |> Map.merge(raw)
    key = attrs["key"] || attrs["korean"]
    source_key = if key, do: "#{slug}/#{key}", else: "#{slug}/##{index}"
    label = "#{file}: item #{index} (#{key || "no key"})"

    attrs =
      attrs
      |> Map.delete("key")
      |> Map.merge(%{"source_key" => source_key, "position" => index, "retired" => false})

    {label, attrs, unknown_keys(raw, @item_keys, label)}
  end

  defp build_item({_raw, index}, _defaults, _slug, file),
    do: {nil, nil, ["#{file}: item #{index} must be a map"]}

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

    planned =
      Enum.map(packs, fn pack ->
        deck = Deck.import_changeset(existing_decks[pack.slug] || %Deck{}, pack.deck)

        items =
          for {label, attrs, []} <- pack.items do
            existing = existing_items[attrs["source_key"]] || %Item{}
            {label, Item.import_changeset(existing, attrs)}
          end

        %{file: pack.file, slug: pack.slug, deck: deck, items: items}
      end)

    errors =
      duplicates(Enum.map(packs, & &1.slug), "deck slug") ++
        duplicates(
          for(pack <- packs, {_, attrs, _} <- pack.items, do: attrs["source_key"]),
          "item key"
        ) ++
        Enum.flat_map(planned, fn pack ->
          changeset_errors(pack.deck, "#{pack.file}: deck") ++
            Enum.flat_map(pack.items, fn {label, cs} -> changeset_errors(cs, label) end)
        end)

    case errors do
      [] -> {:ok, planned}
      errors -> {:error, errors}
    end
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
      stats =
        Enum.reduce(planned, %{decks: @empty_stats, items: @empty_stats}, fn pack, stats ->
          {deck_result, deck} = save(pack.deck)

          Enum.reduce(pack.items, bump(stats, :decks, deck_result), fn {_label, cs}, stats ->
            {item_result, _item} = save(Changeset.put_change(cs, :deck_id, deck.id))
            bump(stats, :items, item_result)
          end)
        end)

      slugs = Enum.map(planned, & &1.slug)
      keys = for pack <- planned, {_, cs} <- pack.items, do: Changeset.get_field(cs, :source_key)
      now = DateTime.utc_now(:second)

      {retired_decks, _} =
        Repo.update_all(from(d in Deck, where: d.slug not in ^slugs and not d.retired),
          set: [retired: true, updated_at: now]
        )

      {retired_items, _} =
        Repo.update_all(from(i in Item, where: i.source_key not in ^keys and not i.retired),
          set: [retired: true, updated_at: now]
        )

      {:ok,
       stats
       |> put_in([:decks, :retired], retired_decks)
       |> put_in([:items, :retired], retired_items)}
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
