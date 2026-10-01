defmodule Hanguko.Audio.Batch do
  @moduledoc """
  Pre-renders many clips at once, for `mix hanguko.audio.generate` and
  `Hanguko.Release.generate_audio/0`.

  The work lives here rather than in the Mix task because a release has no
  Mix: both entry points call these functions and print the result themselves,
  so the loop that spends money exists once.

  Texts are passed in rather than read from `Hanguko.Content`, which keeps the
  audio subsystem unaware of the curriculum. Deciding what is worth
  pronouncing is the caller's business; this module only knows how to buy it in
  bulk without buying anything twice.

  Nothing here raises on a failed clip. One text that the provider refuses
  shouldn't abandon the other two hundred, so failures are collected and
  returned for the caller to report.
  """

  alias Hanguko.Audio

  @max_concurrency 4

  @doc """
  Returns what `generate/2` would synthesize for `texts`, as
  `%{texts: [text], characters: n}`.

  This is what `--dry-run` prints and what a real run prints before it starts,
  so the decision to spend is made against a number rather than a hope. The
  texts are those with no clip yet, found in one query with
  `Hanguko.Audio.urls_for/2`; `characters` counts them the way the provider
  bills and the monthly budget sums, over the canonical form. De-duplication
  goes by that same canonical form rather than by literal spelling, so two
  spellings differing only in spacing or Unicode normalization are one text
  here - one clip serves both, and counting them separately would overstate the
  spend and buy the clip twice.

  Returns `%{texts: [], characters: 0}` when audio is disabled, since no text
  can be matched to a clip without a provider to key it by. A caller that
  wants to tell "nothing to do" from "switched off" checks the provider
  itself.

  Takes the same `:provider`, `:voice` and `:storage` options as
  `Hanguko.Audio.clip_key/2`.
  """
  def pending(texts, opts \\ []) do
    texts = Enum.uniq_by(texts, &Audio.canonical/1)

    if Audio.enabled?(opts) do
      stored = Audio.urls_for(texts, opts)
      missing = Enum.reject(texts, &Map.has_key?(stored, &1))

      %{texts: missing, characters: characters(missing)}
    else
      %{texts: [], characters: 0}
    end
  end

  @doc """
  Synthesizes and stores a clip for each of `texts` that hasn't got one,
  returning `%{generated: n, skipped: n, failed: [{text, reason}]}`.

  Every clip is recorded with `source: :batch`, which keeps pre-rendering the
  curriculum out of the monthly on-demand budget: it is one deliberate spend by
  whoever runs the task, not something to ration per request. No rate limiter
  is involved for the same reason.

  Pass everything worth pronouncing; the misses are worked out here with
  `pending/2`. That is what makes the two counts mean what they say - `generated`
  is clips bought, `skipped` is texts that already had one - and it is why a
  second run reports `generated: 0` rather than counting cache hits as work.

  Runs #{@max_concurrency} texts at a time by default. The provider is a
  network call with retries, so some concurrency matters; too much invites the
  429s that `Hanguko.Audio.Providers.Google` would then have to sit out. Each
  clip waits as long as it needs, since the retries have their own bounds.

  Options: those of `Hanguko.Audio.ensure_clip/2`, plus

    * `:max_concurrency` - how many texts to synthesize at once
  """
  def generate(texts, opts \\ []) do
    texts = Enum.uniq_by(texts, &Audio.canonical/1)

    if Audio.enabled?(opts) do
      %{texts: missing} = pending(texts, opts)
      opts = Keyword.put(opts, :source, :batch)

      {generated, failed} =
        tally(missing, opts, fn text -> {text, Audio.ensure_clip(text, opts)} end)

      %{generated: generated, skipped: length(texts) - length(missing), failed: failed}
    else
      %{generated: 0, skipped: 0, failed: Enum.map(texts, &{&1, :disabled})}
    end
  end

  @doc """
  Re-synthesizes every clip whose audio has gone missing from storage,
  returning `%{repaired: n, failed: [{text, reason}]}`.

  This is what `--verify` does. `Hanguko.Audio.ensure_clip/2` will never notice
  such a clip - a row is its record that the text has been paid for - so
  without this pass a clip whose file vanished serves a permanent 404 and no
  amount of regenerating fixes it.

  Repair is idempotent because keys are content-addressed: the same text gives
  the same key and the same path, so a file that was fine is rewritten with the
  same bytes. Clips recorded under another provider or voice are left alone;
  see `Hanguko.Audio.orphaned_clips/1`.

  Takes the same options as `generate/2`.
  """
  def repair(opts \\ []) do
    {repaired, failed} =
      opts
      |> Audio.orphaned_clips()
      |> tally(opts, fn clip -> {clip.text, Audio.rewrite_clip(clip, opts)} end)

    %{repaired: repaired, failed: failed}
  end

  # Runs `fun` over `items` with bounded concurrency, counting the successes
  # and pairing each failure with the text it was for. `timeout: :infinity`
  # because the provider already bounds its own attempts, and a clip that took
  # longer than some arbitrary limit has still been paid for.
  defp tally(items, opts, fun) do
    {ok, failed} =
      items
      |> Task.async_stream(fun,
        max_concurrency: Keyword.get(opts, :max_concurrency, @max_concurrency),
        timeout: :infinity
      )
      |> Enum.reduce({0, []}, fn
        {:ok, {_text, {:ok, _clip}}}, {ok, failed} -> {ok + 1, failed}
        {:ok, {text, {:error, reason}}}, {ok, failed} -> {ok, [{text, reason} | failed]}
      end)

    {ok, Enum.reverse(failed)}
  end

  defp characters(texts) do
    Enum.reduce(texts, 0, &(String.length(Audio.canonical(&1)) + &2))
  end
end
