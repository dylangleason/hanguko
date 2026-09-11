defmodule Hanguko.Repo.Migrations.CreateContentTables do
  use Ecto.Migration

  def change do
    create table(:decks) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :title_ko, :string
      add :kind, :string, null: false
      add :level, :integer, null: false, default: 1
      add :position, :integer, null: false, default: 0
      add :description, :text
      add :retired, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:decks, [:slug])
    create index(:decks, [:kind, :level, :position])

    create table(:items) do
      add :deck_id, references(:decks, on_delete: :restrict), null: false
      add :source_key, :string, null: false
      add :kind, :string, null: false
      add :korean, :string, null: false
      add :romanization, :string
      add :meaning, :string, null: false
      add :part_of_speech, :string
      add :hint, :text
      add :notes, :text
      add :tags, {:array, :string}, null: false, default: []
      add :position, :integer, null: false
      add :metadata, :map, null: false, default: %{}
      add :retired, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:items, [:source_key])
    create index(:items, [:deck_id, :position])
  end
end
