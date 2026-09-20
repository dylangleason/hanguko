defmodule Hanguko.Audio do
  @moduledoc """
  Implements behaviors for interacting with the audio subsystem of
  the Hanguko application, including generating audio clips with an
  audio API provider, caching audio clips, tracking API limits, and
  disabling audio when no provider is configured.
  """

  alias Hanguko.Korean

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

    :crypto.hash(:sha256, "#{provider.name()}|#{voice}|#{canonical(text)}")
    |> Base.encode16(case: :lower)
  end

  defp canonical(text) do
    text |> String.trim() |> String.split() |> Enum.join(" ") |> Korean.nfc()
  end

  defp configured_provider, do: Application.get_env(:hanguko, __MODULE__, [])[:provider]

  defp configured_voice,
    do: Application.get_env(:hanguko, __MODULE__, [])[:voice]
end
