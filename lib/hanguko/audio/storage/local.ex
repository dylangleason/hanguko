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
      write_atomically(fp, data)
    end
  end

  # `Hanguko.Audio` allows two callers to miss the same text and both
  # synthesize it, and `rewrite_clip/2` says a second render isn't guaranteed to
  # be byte for byte the first, so two writers can hold different bytes for one
  # path. Writing in place would let them interleave into a file matching
  # neither, and whose length matches neither row's `byte_size`. A rename is
  # atomic, so every reader sees one whole version or the other - which is what
  # `Hanguko.Audio.Storage` means by requiring `put/3` to be idempotent.
  defp write_atomically(fp, data) do
    tmp = "#{fp}.#{System.unique_integer([:positive])}.tmp"

    with :ok <- File.write(tmp, data),
         :ok <- File.rename(tmp, fp) do
      :ok
    else
      {:error, reason} ->
        File.rm(tmp)
        {:error, reason}
    end
  end

  @impl true
  def exists?(path) do
    path = full_path(path)
    File.exists?(path) and not File.dir?(path)
  end

  @impl true
  def url(path), do: Hanguko.Audio.config!(:storage_url_prefix) |> Path.join(path)

  @doc """
  Returns the directory clips are written to and served from.

  `HangukoWeb.Endpoint` passes this as an MFA tuple to `Plug.Static`, which
  calls it per request. Endpoint plugs are initialised at compile time, while
  the directory is runtime configuration - in production it comes from
  `AUDIO_DIR` and must be a mounted volume, which no compiled-in path can name.
  """
  def root, do: Hanguko.Audio.config!(:storage_dir)

  @doc """
  Returns the path on disk for a stored clip, under `root/0`.
  """
  def full_path(path) do
    Path.join(root(), path)
  end
end
