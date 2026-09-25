defmodule Hanguko.Fakes.FailingAudioProvider do
  @moduledoc false

  @behaviour Hanguko.Audio.Provider

  @impl true
  def name, do: "failing"

  @impl true
  def synthesize(_text, _voice), do: {:error, :synthesis_failed}
end
