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

  alias Hanguko.Accounts.Scope
  alias Hanguko.Audio.Clip
  alias Hanguko.Audio.Queries
  alias Hanguko.Audio.RateLimiter
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
  Returns whether audio is switched on, that is, whether a provider is
  configured.

  Absence of a provider is a supported state, not a misconfiguration: the app
  runs without an API key and every page falls back to the browser's own
  speech. This is how a caller with no error channel - a Mix task deciding
  whether to start, a page deciding whether to offer a speak button - asks,
  rather than reading the config itself.

  Takes the same `:provider` option as `clip_key/2`.
  """
  def enabled?(opts \\ []), do: not is_nil(get_provider(opts))

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
  Returns `{:ok, url}` for `text` on behalf of the learner in `scope`,
  synthesizing it if no clip exists. This is the entry point for audio a person
  asked for in the moment, and the only one that applies limits.

  Checks run cheapest first, and only a miss is ever limited:

    1. no signed-in user - `{:error, :unauthenticated}`. Anonymous visitors get
       browser speech; synthesis is attributable or it doesn't happen
    2. no provider configured - `{:error, :disabled}`
    3. a stored clip - `{:ok, url}` immediately. Replaying audio costs nothing,
       so it takes no rate-limit slot and no budget
    4. `Hanguko.Audio.RateLimiter` - `{:error, :rate_limited}` when this user
       has spent their allowance for the hour
    5. the monthly budget - `{:error, :budget_exceeded}` when this month's
       on-demand characters, plus this request's own, would pass the cap. The
       request counts itself, so one long text can't step over the cap. The cap
       is shared rather than per learner, so this is the one error here that
       isn't about the caller: see `characters_used/1`
    6. `ensure_clip/2` with `source: :on_demand` and this user recorded

  Anything `ensure_clip/2` reports comes back unchanged, including
  `{:error, :invalid_text}` and provider or storage failures. Every error is
  something the caller can act on by falling back to browser speech, which is
  why none of them raise.

  `now` is passed in, as in `Hanguko.SRS.review_card/5`, so the hour the
  limiter counts and the month the budget sums are the caller's to decide.

  Options: those of `ensure_clip/2`, plus

    * `:limiter` - options passed straight through to
      `Hanguko.Audio.RateLimiter.take/3`, such as `[name: ..., limit: ...]`.
      They are that module's to name, not this one's
    * `:budget` - overrides the configured monthly character cap

  Being able to override both limits per call is what lets the tests stay
  async, with no `Application.put_env`.
  """

  def speak(scope, text, now, opts \\ [])
  def speak(nil, _text, _now, _opts), do: {:error, :unauthenticated}
  def speak(%Scope{user: nil}, _text, _now, _opts), do: {:error, :unauthenticated}

  def speak(%Scope{user: user}, text, now, opts) do
    case get_provider(opts) do
      nil ->
        {:error, :disabled}

      _ ->
        key = clip_key(text, opts)
        clip = get_clip(key)
        storage = get_storage(opts)

        if is_nil(clip) do
          opts = Keyword.merge(opts, requested_by_id: user.id, source: :on_demand)

          with :ok <- RateLimiter.take(user.id, now, Keyword.get(opts, :limiter, [])),
               :ok <- check_budget(text, now, opts),
               {:ok, clip} <- ensure_clip(text, opts) do
            {:ok, clip.storage_path |> storage.url()}
          else
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok, clip.storage_path |> storage.url()}
        end
    end
  end

  defp check_budget(text, now, opts) do
    count = characters_used(now) + String.length(canonical(text))
    budget = Keyword.get_lazy(opts, :budget, &configured_budget/0)

    if count > budget do
      {:error, :budget_exceeded}
    else
      :ok
    end
  end

  @doc """
  Returns how many characters on-demand synthesis has spent in the calendar
  month containing `now`, in UTC.

  The month is UTC rather than the learner's timezone because this counts one
  shared bill, not one person's activity; a learner's own day boundary
  (`Hanguko.SRS.Day`) has nothing to do with it. Batch generation is excluded:
  pre-rendering the curriculum is a decision made once by whoever runs the
  task, not something to ration.

  One bill means one allowance, deliberately: there is no per-learner share of
  it. The consequence is worth stating plainly, because it is not the usual
  shape of a limit - whoever spends the last of the month's characters drops
  *every* learner to browser speech until the month turns, not only themselves.
  `Hanguko.Audio.RateLimiter` caps how fast any one account can spend, which
  makes reaching that point slow rather than impossible.
  """
  def characters_used(now) do
    this_month = now |> Date.beginning_of_month() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    Queries.clips()
    |> Queries.with_source(:on_demand)
    |> Queries.inserted_since(this_month)
    |> Queries.sum_characters()
    |> Repo.one()
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
        clip = get_clip(key)

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
         {:ok, %{data: data, content_type: content_type, path: path}} <-
           store_clip(text, voice, key, provider, storage) do
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
  Returns the clips whose audio is no longer in storage, for
  `mix hanguko.audio.generate --verify` to repair.

  Only clips matching the configured provider and voice are considered. A clip
  recorded under another voice keys to audio this configuration cannot
  reproduce (`clip_key/2` hashes the voice), so regenerating it would write
  different speech at a path that claims to be the old one. Those clips are
  left alone: they are stale, not broken.

  One `c:Hanguko.Audio.Storage.exists?/1` call per clip, which is a stat per
  file on local storage. Fine for a few hundred clips run from a Mix task, and
  not something to put on a request path.

  Raises when no provider is configured. A list has no error channel, and
  answering "no orphans" for a subsystem that is switched off would be a lie;
  callers establish that audio is enabled before asking.

  Takes the same `:provider`, `:voice` and `:storage` options as `clip_key/2`.
  """
  def orphaned_clips(opts \\ []) do
    provider = get_provider(opts) || raise "no audio provider is configured"
    voice = get_voice(opts)
    storage = get_storage(opts)

    clips =
      Queries.clips()
      |> Queries.with_provider(provider.name())
      |> Queries.with_voice(voice)
      |> Repo.all()

    for clip <- clips, not storage.exists?(clip.storage_path), do: clip
  end

  @doc """
  Re-synthesizes `clip` and writes it back to its existing path, returning
  `{:ok, clip}` with the row brought in line with the new bytes.

  This is the repair half of `--verify`, and the one place audio is bought for
  a text that already has a row. `ensure_clip/2` deliberately won't: a row is
  its record that the text has been paid for.

  The key and the text are untouched, since both are derived from content that
  hasn't changed. `byte_size`, `content_type` and `storage_path` are taken from
  the new synthesis: a second render of the same text is not guaranteed to
  return byte for byte what the first one did, and the path follows the content
  type, so a provider that begins answering in another format moves the file
  instead of leaving the row describing one that isn't there. Whatever was at
  the old path stays there, unreferenced.

  Errors:

    * `{:error, :disabled}` - no provider is configured
    * `{:error, :provider_mismatch}` - `clip` was made by another provider or
      voice than the configured one, so its key cannot be reproduced. The
      caller should regenerate under the current configuration instead, which
      gives a different key and leaves this row as it is
    * `{:error, term}` - the provider or storage failed. The row keeps pointing
      at the missing object, and the next `--verify` tries again

  Takes the same options as `ensure_clip/2`, except `:source` and
  `:requested_by_id`, which belong to the row that already exists.
  """
  def rewrite_clip(%Clip{} = clip, opts \\ []) do
    case get_provider(opts) do
      nil ->
        {:error, :disabled}

      provider ->
        with true <- provider.name() == clip.provider and get_voice(opts) == clip.voice,
             {:ok, %{data: data, content_type: content_type, path: path}} <-
               store_clip(clip.text, clip.voice, clip.key, provider, get_storage(opts)) do
          clip
          |> Clip.changeset(%{
            byte_size: byte_size(data),
            content_type: content_type,
            storage_path: path
          })
          |> Repo.update()
        else
          false -> {:error, :provider_mismatch}
          {:error, reason} -> {:error, reason}
        end
    end
  end

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

  defp store_clip(text, voice, key, provider, storage) do
    with {:ok, %{data: data, content_type: content_type}} <- provider.synthesize(text, voice),
         path <- storage_path(key, content_type),
         :ok <- storage.put(path, data, content_type) do
      {:ok, %{data: data, path: path, content_type: content_type}}
    end
  end

  defp valid_text?(text), do: String.length(canonical(text)) <= 200 and Korean.text?(text)

  defp get_provider(opts), do: Keyword.get_lazy(opts, :provider, &configured_provider/0)

  defp get_storage(opts), do: Keyword.get_lazy(opts, :storage, &configured_storage/0)

  defp get_voice(opts), do: Keyword.get_lazy(opts, :voice, &configured_voice/0)

  defp configured_provider, do: Application.get_env(:hanguko, __MODULE__, [])[:provider]

  defp configured_storage, do: config!(:storage)

  defp configured_voice, do: config!(:voice)

  defp configured_budget, do: config!(:characters_per_month)

  defp config!(key), do: :hanguko |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
