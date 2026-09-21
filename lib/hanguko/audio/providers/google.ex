defmodule Hanguko.Audio.Providers.Google do
  @behaviour Hanguko.Audio.Provider

  def name, do: "google"

  def synthesize(_text, _voice) do
    {:error, :not_implemented}
  end
end
