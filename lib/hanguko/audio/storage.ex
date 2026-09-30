defmodule Hanguko.Audio.Storage do
  @moduledoc """
  Storage defines a contract for writing audio clips to a storage device.
  """

  @doc """
  Writes the data to the specified path to a the storage device and
  return `:ok` if successful, an `:error` tuple if not. Must be idempotent.
  """
  @callback put(path :: String.t(), data :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Returns whether an object is present at `path`.

  Used by `mix hanguko.audio.generate --verify` to find clip rows whose audio
  has gone missing. Rows and objects drift apart for reasons no write ordering
  prevents - a volume that wasn't mounted when the clip was written, a
  directory cleaned by hand - and `Hanguko.Audio.ensure_clip/2` never revisits
  a text once its row exists, so nothing else would ever notice.
  """
  @callback exists?(path :: String.t()) :: boolean()

  @doc """
  Returns a URL the browser uses to fetch a clip at `path`. Derived on demand
  and never persisted, so moving storage or adding a CDN doesn't require migration.
  """
  @callback url(path :: String.t()) :: String.t()
end
