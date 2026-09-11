defmodule Hanguko.Repo.Migrations.CreateStudySettings do
  use Ecto.Migration

  def change do
    create table(:study_settings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :daily_new_limit, :integer, null: false, default: 10
      add :daily_review_limit, :integer, null: false, default: 200
      add :desired_retention, :float, null: false, default: 0.9
      # nil until detected from the browser (or set by the user)
      add :timezone, :text
      add :day_rollover_hour, :integer, null: false, default: 4
      add :show_romanization, :boolean, null: false, default: true
      add :tts_rate, :float, null: false, default: 0.9

      timestamps(type: :utc_datetime)
    end

    create unique_index(:study_settings, [:user_id])
  end
end
