defmodule Hanguko.Fakes.RacingAudioProvider do
  @moduledoc false

  # Simulates another process winning the race for the same clip. `synthesize/2`
  # runs after `ensure_clip/2` has already looked the key up and missed, so the
  # row this inserts is exactly the concurrent insert that the real conflict
  # handling has to cope with — and it happens on every run, rather than when
  # the scheduler happens to interleave two tasks.
  #
  # The row is marked `source: :batch` with `byte_size: 0`, neither of which
  # `ensure_clip/2` would produce on this path, so a test can tell the winner's
  # row apart from the struct the caller built for itself.

  @behaviour Hanguko.Audio.Provider

  alias Hanguko.Audio
  alias Hanguko.Audio.Clip
  alias Hanguko.Repo

  @content_type "audio/mpeg"

  @impl true
  def name, do: "racing"

  @impl true
  def synthesize(text, voice) do
    text = Audio.canonical(text)
    key = Audio.clip_key(text, provider: __MODULE__, voice: voice)

    Repo.insert!(%Clip{
      key: key,
      text: text,
      provider: name(),
      voice: voice,
      storage_path: Audio.storage_path(key, @content_type),
      content_type: @content_type,
      source: :batch,
      byte_size: 0,
      characters: String.length(text)
    })

    {:ok, %{data: :crypto.hash(:sha256, text), content_type: @content_type}}
  end
end
