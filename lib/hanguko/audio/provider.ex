defmodule Hanguko.Audio.Provider do
  @callback name() :: String.t()
  @callback synthesize(text :: String.t(), voice :: String.t()) ::
              {:ok, %{data: binary(), content_type: String.t()}} | {:error, term()}
end
