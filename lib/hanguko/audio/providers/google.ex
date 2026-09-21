defmodule Hanguko.Audio.Providers.Google do
  @moduledoc """
  Google implements the audio provider contract and synthesize text to speech
  using the Google TTS APIs.
  """
  @behaviour Hanguko.Audio.Provider

  @impl true
  def name, do: "google"

  @impl true
  def synthesize(_text, _voice) do
    {:error, :not_implemented}
  end
end
