defmodule Hanguko.Repo.Migrations.CreateGrammarTables do
  use Ecto.Migration

  def change do
    create table(:grammar_points) do
      add :slug, :text, null: false
      add :title, :text, null: false
      add :pattern, :text, null: false
      add :summary, :text
      add :level, :integer, null: false, default: 1
      add :position, :integer, null: false, default: 0
      add :explanation, :text, null: false
      # A list of %{"when" => ..., "form" => ..., "example" => ...} rows,
      # shown as the formation table.
      add :formation, :map, null: false, default: fragment("'[]'::jsonb")
      add :retired, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:grammar_points, [:slug])
    create index(:grammar_points, [:level, :position])

    create table(:grammar_progress) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :grammar_point_id, references(:grammar_points, on_delete: :delete_all), null: false

      add :learned_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:grammar_progress, [:user_id, :grammar_point_id])
    create index(:grammar_progress, [:grammar_point_id])

    alter table(:items) do
      # Example sentences point at the grammar they demonstrate; `cloze` is the
      # part of `korean` that is blanked out when the sentence is studied.
      add :grammar_point_id, references(:grammar_points, on_delete: :restrict)
      add :cloze, :text
    end

    create index(:items, [:grammar_point_id])
  end
end
