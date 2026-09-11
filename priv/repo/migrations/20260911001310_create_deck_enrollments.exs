defmodule Hanguko.Repo.Migrations.CreateDeckEnrollments do
  use Ecto.Migration

  def change do
    create table(:deck_enrollments) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :deck_id, references(:decks, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:deck_enrollments, [:user_id, :deck_id])
    create index(:deck_enrollments, [:deck_id])
  end
end
