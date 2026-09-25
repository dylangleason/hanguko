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

  alias Hanguko.Audio.Clip
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
    provider = Keyword.get_lazy(opts, :provider, &configured_provider/0)

    if provider do
      opts = Keyword.put(opts, :provider, provider)
      storage = Keyword.get_lazy(opts, :storage, &configured_storage/0)

      keys = Map.new(texts, &{&1, clip_key(&1, opts)})

      urls =
        Queries.clips()
        |> Queries.with_key(Map.values(keys))
        |> Queries.to_map([:key, :storage_path])
        |> Repo.all()
        |> Map.new(&{&1.key, storage.url(&1.storage_path)})

      for {text, key} <- keys, url = urls[key], into: %{}, do: {text, url}
    else
      %{}
    end
  end

  @doc """
  Returns `{:ok, clip}` for `text`, synthesizing and storing the audio only
  if no clip exists yet. This is the only function that spends provider quota.

  On a hit the stored `Hanguko.Audio.Clip` is returned as is, without reaching
  the provider or storage. On a miss the text is validated, the provider
  synthesizes it, the bytes are written to storage, and only then is the row
  inserted, so a clip row never points at an object that isn't there.

  The row records the canonical text (`canonical/1`), which is the form the key
  is derived from, so texts differing only in spacing resolve to one clip. Its
  `characters` is the length of that canonical text, since that is what was
  actually sent to the provider and what the monthly budget counts.

  Two callers can miss at the same time and both synthesize. The insert uses
  `on_conflict: :nothing` and re-reads by key, so the loser returns the winner's
  clip rather than failing on the unique index; the duplicate write is harmless
  because `c:Hanguko.Audio.Storage.put/3` is idempotent and the bytes land at
  the same key-derived path.

  Errors:

    * `{:error, :disabled}` - no provider is configured, so nothing can be
      synthesized and the caller falls back to browser speech
    * `{:error, :invalid_text}` - the text is not worth synthesizing: it has no
      Hangul, contains characters other than Hangul, spaces and punctuation, or
      is longer than 200 characters. Checked only on a miss, so an existing clip
      is still returned
    * `{:error, term}` - the provider or the storage backend failed. Nothing is
      inserted, so the next request tries again

  Options:

    * `:source` - `:on_demand` (default) or `:batch`, recorded on the clip and
      used by the monthly budget query. The default is the metered path, so a
      caller that forgets to say `source: :batch` overcounts rather than
      letting synthesis through unmetered
    * `:requested_by_id` - the user who triggered an on-demand synthesis, for
      abuse tracking. `nil` (default) for batch generation
    * `:provider`, `:voice`, `:storage` - as in `clip_key/2`, so tests and the
      batch task can pick a backend without touching the application config
  """
  def ensure_clip(text, opts \\ []) do
    case get_provider(opts) do
      nil ->
        {:error, :disabled}

      provider ->
        key = clip_key(text, opts)
        clip = Queries.clips() |> Queries.with_key(key) |> Repo.one()

        if is_nil(clip) do
          write_clip(text, key, provider, opts)
        else
          {:ok, clip}
        end
    end
  end

  defp write_clip(text, key, provider, opts) do
    storage = get_storage(opts)
    voice = get_voice(opts)

    with true <- valid_text?(text),
         {:ok, %{data: data, content_type: content_type}} <- provider.synthesize(text, voice),
         path <- storage_path(key, content_type),
         :ok <- storage.put(path, data, content_type) do
      canonical_text = canonical(text)
      source = Keyword.get(opts, :source, :on_demand)

      clip =
        %Clip{
          key: key,
          text: canonical_text,
          byte_size: byte_size(data),
          characters: String.length(canonical_text),
          provider: provider.name(),
          voice: voice,
          content_type: content_type,
          source: source,
          storage_path: path,
          requested_by_id: opts[:requested_by_id]
        }

      case Repo.insert!(clip, on_conflict: :nothing, conflict_target: :key) do
        %Clip{id: nil} -> {:ok, get_clip(key)}
        inserted -> {:ok, inserted}
      end
    else
      false -> {:error, :invalid_text}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_clip(key), do: Queries.clips() |> Queries.with_key(key) |> Repo.one()

  @doc """
  Returns the form of `text` that the key is derived from and that clips are
  stored with: trimmed, with runs of whitespace collapsed to one space, in
  Unicode NFC. Punctuation and case are kept, since they change how the text
  is read aloud.
  """
  def canonical(text) do
    text |> String.trim() |> String.split() |> Enum.join(" ") |> Korean.nfc()
  end

  @doc """
  Generate the storage path based on the computed `key` and
  `content_type` for the data.
  """
  def storage_path(key, content_type) do
    ext = MIME.extensions(content_type) |> List.first()
    name = if is_nil(ext), do: key, else: "#{key}.#{ext}"

    String.slice(key, 0, 2)
    |> Path.join(String.slice(key, 2, 2))
    |> Path.join(name)
  end

  defp valid_text?(text), do: String.length(canonical(text)) <= 200 and Korean.text?(text)

  defp get_provider(opts), do: Keyword.get_lazy(opts, :provider, &configured_provider/0)

  defp get_storage(opts), do: Keyword.get_lazy(opts, :storage, &configured_storage/0)

  defp get_voice(opts), do: Keyword.get_lazy(opts, :voice, &configured_voice/0)

  defp configured_provider, do: Application.get_env(:hanguko, __MODULE__, [])[:provider]

  defp configured_storage, do: config!(:storage)

  defp configured_voice, do: config!(:voice)

  defp config!(key), do: :hanguko |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
