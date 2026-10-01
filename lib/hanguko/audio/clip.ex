defmodule Hanguko.Audio.Clip do
  @moduledoc """
  A synthesized recording of a piece of Korean text, stored once and shared by every user.

  A clip's key is a hash of the provider, voice and trimmed, NFC-normalized text,
  computed via `Hanguko.Audio.clip_key/2`. The key, text, provider and voice are
  set once and never updated; changing an item's text just points it at a
  different clip. The one exception is `Hanguko.Audio.rewrite_clip/2`, which
  repairs a clip whose file has gone missing from storage by re-synthesizing it
  and updating `byte_size`, `content_type` and `storage_path` via
  `rewrite_changeset/2`.

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
  Validates a new clip for insertion. `requested_by_id` is set by the caller,
  so is not cast. Repairing an existing clip's audio uses `rewrite_changeset/2`
  instead.
  """
  def changeset(clip, attrs) do
    clip
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> unique_constraint(:key)
  end

  @rewrite_fields ~w(byte_size content_type storage_path)a

  @doc """
  Validates a re-synthesis of an existing clip's audio, used by
  `Hanguko.Audio.rewrite_clip/2` to repair a clip whose stored file has gone
  missing. Only the fields a new render can change are cast: the key, text,
  provider and voice identify the clip and are untouched by a repair, so
  `validate_required/2` and `unique_constraint/2` on `:key` don't apply here.
  """
  def rewrite_changeset(clip, attrs) do
    clip
    |> cast(attrs, @rewrite_fields)
    |> validate_required(@rewrite_fields)
  end
end
