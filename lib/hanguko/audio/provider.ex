defmodule Hanguko.Audio.Provider do
  @moduledoc """
  The audio provider is a service that consumes Korean text
  and will synthesize the Korean speech with the specified
  voice configuration.
  """

  @doc """
  Returns a string of the provider name. The name is used
  to generate the key, so changing it orphans existing clips.
  """
  @callback name() :: String.t()

  @doc """
  Transform the Korean text to audio via speech synthesis
  with the desired voice configuration.

  Returns a tuple containing either `:ok` and a map containing
  the audio data (played at normal speed - the browser can adjust playback rate),
  as well as the content type for the data.

  Otherwise, return an error on failure.
  """
  @callback synthesize(text :: String.t(), voice :: String.t()) ::
              {:ok, %{data: binary(), content_type: String.t()}} | {:error, term()}
end
