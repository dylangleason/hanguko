defmodule Hanguko.Audio.Storage.Local do
  @moduledoc """
  Implements the storage behavior and writes the audio content to
  a local file system.
  """

  @behaviour Hanguko.Audio.Storage

  @impl true
  def put(path, data, _content_type) do
    fp = full_path(path)

    with :ok <- Path.dirname(fp) |> File.mkdir_p() do
      File.write(fp, data)
    end
  end

  @impl true
  def url(path) do
    :hanguko
    |> Application.fetch_env!(Hanguko.Audio)
    |> Keyword.fetch!(:storage_url_prefix)
    |> Path.join(path)
  end

  def full_path(path) do
    :hanguko
    |> Application.fetch_env!(Hanguko.Audio)
    |> Keyword.fetch!(:storage_dir)
    |> Path.join(path)
  end
end
