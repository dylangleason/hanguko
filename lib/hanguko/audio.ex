defmodule Hanguko.Audio do
  @moduledoc """
  The audio subsystem turns Korean text into a playable clip, generating
  and storing audio only the first time a given text is requested.

  Each clip is identified by a key derived from its text, provider and voice
  (see `clip_key/2` and `Hanguko.Audio.Clip`). On a miss, this module has the
  configured `Hanguko.Audio.Provider` synthesize the text, stores the bytes
  with the configured `Hanguko.Audio.Storage`, and records the clip. Pages
  turn stored clips into URLs in one batch lookup with `urls_for/2`.

  This is the only module that uses both a provider and a storage backend;
  neither knows about the other or about the database, so each can be
  replaced or faked on its own. When no provider is configured, audio is
  disabled and the browser's own speech synthesis is used instead.
  """

  alias Hanguko.Audio.Queries
  alias Hanguko.Korean
  alias Hanguko.Repo

  @doc """
  Generates a deterministic key for a Korean audio clip based on the text,
  provider and voice configuration. The key is generated using a SHA-256 hash
  and then encoded as a lowercase Base-16 string.

  Prior to hashing, the text is trimmed, repeated spaces removed, then
  normalized via Unicode NFC.
  """
  def clip_key(text, opts \\ []) do
    provider = Keyword.get_lazy(opts, :provider, &configured_provider/0)
    voice = Keyword.get_lazy(opts, :voice, &configured_voice/0)

    case provider do
      nil ->
        nil

      provider ->
        :crypto.hash(:sha256, "#{provider.name()}|#{voice}|#{canonical(text)}")
        |> Base.encode16(case: :lower)
    end
  end

  @doc """
  Returns `%{text => url}` for each of `texts` that already has a clip, in one
  query, so a page can pass `audio={url}` to every speak button it renders
  without a query per button.

  The map is keyed by each text exactly as given, not by its canonical form:
  the caller looks up its own strings, even when two of them (say, with and
  without surrounding spaces) share one clip. Texts with no clip are left out,
  and those buttons fall back to on-demand audio or browser speech.

  Returns an empty map when audio is disabled, since no clip can match
  without a provider to key it by.

  Takes the same `:provider` and `:voice` options as `clip_key/2`.
  """
  def urls_for(texts, opts \\ []) do
    {canonical_texts, keys} =
      for text <- texts, reduce: {MapSet.new(), []} do
        {a, b} -> {MapSet.put(a, canonical(text)), b ++ [clip_key(text, opts)]}
      end

    case Enum.reject(keys, &is_nil/1) do
      [] ->
        %{}

      keys ->
        storage = Keyword.get_lazy(opts, :storage, &configured_storage/0)

        text_map =
          Queries.clips()
          |> Queries.with_key(keys)
          |> Queries.to_map([:text, :storage_path])
          |> Repo.all()
          |> Enum.map(&{&1[:text], storage.url(&1[:storage_path])})
          |> Enum.into(%{})

        # Get a diff of any remaining texts that are in non-canonical form
        # and add them as keys back to the text map, pointing them the same URL
        # as their canonical form.
        texts
        |> MapSet.new()
        |> MapSet.difference(canonical_texts)
        |> Enum.reduce(text_map, fn item, acc ->
          case acc[canonical(item)] do
            nil -> acc
            url -> Map.put(acc, item, url)
          end
        end)
    end
  end

  def canonical(text) do
    text |> String.trim() |> String.split() |> Enum.join(" ") |> Korean.nfc()
  end

  defp configured_provider, do: Application.get_env(:hanguko, __MODULE__, [])[:provider]

  defp configured_storage, do: Application.get_env(:hanguko, __MODULE__, [])[:storage]

  defp configured_voice,
    do: Application.get_env(:hanguko, __MODULE__, [])[:voice]
end
