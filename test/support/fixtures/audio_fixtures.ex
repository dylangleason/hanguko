defmodule Hanguko.AudioFixtures do
  @moduledoc """
  Test helpers for inserting audio clips directly, without synthesizing them.
  """

  alias Hanguko.Audio
  alias Hanguko.Audio.Clip
  alias Hanguko.Repo

  @doc """
  Inserts a clip for `text`, keyed with `Hanguko.Audio.clip_key/2` under the
  test configuration, so `Hanguko.Audio` finds it as if it had been
  synthesized. `attrs` overrides the defaults. Returns the inserted
  `Hanguko.Audio.Clip`.
  """
  def clip_fixture(text, attrs \\ %{}) do
    {provider, attrs} = pop_attr!(attrs, :provider)
    {voice, attrs} = pop_attr!(attrs, :voice)

    key = Audio.clip_key(text)

    storage_path =
      String.slice(key, 0, 2)
      |> Path.join(String.slice(key, 2, 2))
      |> Path.join("voice.mp3")

    %Clip{
      key: key,
      text: Audio.canonical(text),
      # byte_size should actually be audio for real, non test
      # data. just use text here as the input since it doesn't really
      # matter for the fixture
      byte_size: byte_size(text),
      characters: String.length(Hanguko.Audio.canonical(text)),
      provider: provider.name(),
      voice: voice,
      storage_path: storage_path,
      content_type: "audio/mpeg",
      source: :batch
    }
    |> struct(Map.new(attrs))
    |> Repo.insert!()
  end

  defp pop_attr!(attrs, value) do
    Map.pop_lazy(Map.new(attrs), value, fn ->
      Application.fetch_env!(:hanguko, Hanguko.Audio) |> Keyword.fetch!(value)
    end)
  end
end
