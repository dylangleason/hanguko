defmodule Mix.Tasks.Hanguko.Audio.Generate do
  @shortdoc "Pre-renders audio for the curriculum with the configured TTS provider"

  @moduledoc """
  Synthesizes a clip for everything the live curriculum says out loud, so a
  learner never waits on the provider for content that was known in advance.

      $ mix hanguko.audio.generate --dry-run
      $ mix hanguko.audio.generate
      $ mix hanguko.audio.generate --verify

  Texts come from `Hanguko.Content.speech_texts/0` and clips are recorded with
  `source: :batch`, which keeps this spend out of the monthly on-demand budget:
  pre-rendering the curriculum is one decision by whoever runs the task, not
  something to ration per request.

  Safe to run repeatedly. Clips are keyed by a hash of their text, provider and
  voice, so a second run has nothing to do and costs nothing. Run it after every
  content import, and after changing the voice - a new voice is a new key for
  every phrase, which is a whole regeneration.

  ## Options

    * `--dry-run` - print what would be synthesized and stop. Nothing reaches
      the provider, so this is the safe way to see what a voice change costs
    * `--verify` - re-synthesize clips whose audio has gone missing from
      storage. Rows and files drift apart for reasons no write ordering
      prevents - a volume that wasn't mounted, a directory cleaned by hand, a
      restore from an older snapshot - and nothing else ever revisits a text
      once its row exists. Idempotent, since regenerating gives the same key
      and the same path

  Raises when no provider is configured, rather than reporting nothing to do:
  asking to generate audio with synthesis switched off is a mistake worth
  hearing about. It also raises after reporting any clip that failed, so a
  scripted run exits non-zero.

  `Hanguko.Release.generate_audio/0` is the same task for a release, where Mix
  isn't available.
  """
  use Mix.Task

  alias Hanguko.Audio
  alias Hanguko.Audio.Batch
  alias Hanguko.Content

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [dry_run: :boolean, verify: :boolean])
    Logger.configure(level: :info)

    unless Audio.enabled?() do
      Mix.raise("No audio provider is configured; set GOOGLE_TTS_API_KEY to generate audio")
    end

    if opts[:verify], do: repair(), else: generate(opts[:dry_run])
  end

  defp generate(dry_run?) do
    texts = Content.speech_texts()
    %{texts: missing, characters: characters} = Batch.pending(texts)

    Mix.shell().info("#{length(missing)} clips to generate, #{characters} characters")

    unless dry_run? do
      %{generated: generated, skipped: skipped, failed: failed} = Batch.generate(texts)

      Mix.shell().info("  #{generated} generated, #{skipped} already stored")
      report(failed)
    end
  end

  defp repair do
    %{repaired: repaired, failed: failed} = Batch.repair()

    Mix.shell().info("  #{repaired} repaired")
    report(failed)
  end

  defp report([]), do: :ok

  defp report(failures) do
    Enum.each(failures, fn {text, reason} ->
      Mix.shell().error("  #{text}: #{inspect(reason)}")
    end)

    Mix.raise("#{length(failures)} clip(s) failed; nothing else was left unfinished")
  end
end
