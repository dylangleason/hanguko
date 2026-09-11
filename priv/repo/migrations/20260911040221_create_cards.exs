defmodule Hanguko.Repo.Migrations.CreateCards do
  use Ecto.Migration

  def change do
    create table(:cards) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :item_id, references(:items, on_delete: :restrict), null: false
      add :template, :text, null: false
      # FSRS scheduling state
      add :state, :text, null: false
      add :step, :integer
      add :stability, :float
      add :difficulty, :float
      add :due, :utc_datetime, null: false
      add :last_review_at, :utc_datetime
      add :reps, :integer, null: false, default: 0
      add :lapses, :integer, null: false, default: 0
      add :suspended, :boolean, null: false, default: false
      # When the card was first studied; counts against the daily new limit.
      add :introduced_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cards, [:user_id, :item_id, :template])
    create index(:cards, [:user_id, :due])
    create index(:cards, [:user_id, :introduced_at])
    create index(:cards, [:item_id])
  end
end
