defmodule Hanguko.Audio.Clip do
  @moduledoc """
  A synthesized recording of a piece of Korean text, stored once and shared by every user.

  A clip's key is a hash of the provider, voice and trimmed, NFC-normalized text,
  computed via `Hanguko.Audio.clip_key/2`. It is never updated, and changing an item's
  text just points it at a different clip.

  Clips can be requested on demand by a user or generated in batch.
  When audio clips are generated in batch, then the `requested_by` field
  for that clip will be `nil`; `requested_by` records who triggered an
  on-demand synthesis, for abuse tracking and budgets.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @fields ~w(key text provider voice storage_path content_type source byte_size characters)a

  schema "audio_clips" do
    field :key, :string
    field :text, :string
    field :provider, :string
    field :voice, :string
    field :storage_path, :string
    field :content_type, :string
    field :source, Ecto.Enum, values: [:batch, :on_demand]
    field :byte_size, :integer
    field :characters, :integer

    belongs_to :requested_by, Hanguko.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Validates a new clip. Clips are inserted once and never updated.
  `requested_by_id` is set by the caller, so is not cast.
  """
  def changeset(clip, attrs) do
    clip
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> unique_constraint(:key)
  end
end
