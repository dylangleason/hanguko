defmodule Hanguko.Repo.Migrations.CreateAudioClips do
  use Ecto.Migration

  def change do
    create table(:audio_clips) do
      add :key, :text, null: false
      add :text, :text, null: false
      add :provider, :text, null: false
      add :voice, :text, null: false
      add :storage_path, :text, null: false
      add :content_type, :text, null: false
      add :source, :text, null: false
      add :byte_size, :integer, null: false
      add :characters, :integer, null: false
      add :requested_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:audio_clips, [:key])
    create index(:audio_clips, [:source, :inserted_at])
    create index(:audio_clips, [:requested_by_id])
  end
end
