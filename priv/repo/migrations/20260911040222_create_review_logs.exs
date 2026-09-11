defmodule Hanguko.Repo.Migrations.CreateReviewLogs do
  use Ecto.Migration

  def change do
    create table(:review_logs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :card_id, references(:cards, on_delete: :delete_all), null: false
      add :rating, :integer, null: false
      add :reviewed_at, :utc_datetime, null: false
      add :duration_ms, :integer
      # Days since the previous review (nil for a card's first review)
      add :elapsed_days, :integer
      # Seconds until the card is due again
      add :scheduled_seconds, :integer, null: false

      # The card's scheduling fields before the review (state nil = new card),
      # kept for undo and for optimizing FSRS parameters later.
      add :state_before, :text
      add :step_before, :integer
      add :stability_before, :float
      add :difficulty_before, :float
      add :due_before, :utc_datetime
      add :last_review_before, :utc_datetime

      add :state_after, :text, null: false
      add :stability_after, :float
      add :difficulty_after, :float

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:review_logs, [:user_id, :reviewed_at])
    create index(:review_logs, [:card_id])
  end
end
