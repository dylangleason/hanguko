defmodule Hanguko.Audio.Providers.Fake do
  @behaviour Hanguko.Audio.Provider

  def name, do: "fake"

  def synthesize(_text, _voice) do
    {:error, :not_implemented}
  end
end
