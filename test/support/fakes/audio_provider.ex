defmodule Hanguko.Fakes.AudioProvider do
  @moduledoc false

  @behaviour Hanguko.Audio.Provider

  @impl true
  def name, do: "fake"

  @impl true
  def synthesize(text, voice) do
    send(test_pid(), {__MODULE__, :synthesize, text, voice})
    {:ok, %{data: :crypto.hash(:sha256, text), content_type: "audio/mpeg"}}
  end

  defp test_pid, do: :"$callers" |> Process.get([]) |> List.last() || self()
end
