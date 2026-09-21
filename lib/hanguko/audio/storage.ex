defmodule Hanguko.Audio.Storage do
  @moduledoc """
  Storage defines a contract for writing audio clips to a storage device.
  """

  @doc """
  Write the data to the specified path to a the storage device and
  return `:ok` if successful, an `:error` tuple if not. Must be idempotent.
  """
  @callback put(path :: String.t(), data :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Return a URL for the given path, suitable for tracking a
  a clip entry in the database
  """
  @callback url(path :: String.t()) :: String.t()
end
