defmodule Hanguko.Audio.Queries do
  @moduledoc """
  Queries over audio clips, used by `Hanguko.Audio`.

  Functions here build `Ecto.Query` structs and never touch the database; the
  caller decides what to run. Queries name their binding `:clip`, so the
  narrowing functions can be chained onto any query that has it.
  """
  import Ecto.Query, warn: false

  alias Hanguko.Audio.Clip

  @doc "All clips, bound as `:clip`."
  def clips, do: from(c in Clip, as: :clip)

  @doc """
  Narrows `query` to the clips with `key`, or with any of the keys when given
  a list. A single key matches at most one clip, since keys are unique.
  """
  def with_key(query, keys) when is_list(keys), do: where(query, [clip: c], c.key in ^keys)
  def with_key(query, key), do: where(query, [clip: c], c.key == ^key)

  @doc """
  Selects the given clip `fields` into a map
  """
  def to_map(query, fields), do: select(query, [clip: c], map(c, ^fields))
end
