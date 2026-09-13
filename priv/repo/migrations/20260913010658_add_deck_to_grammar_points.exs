defmodule Hanguko.Repo.Migrations.AddDeckToGrammarPoints do
  use Ecto.Migration

  def change do
    alter table(:grammar_points) do
      # The deck holding the point's example sentences, which also places it
      # in the curriculum.
      add :deck_id, references(:decks, on_delete: :restrict)
    end

    create index(:grammar_points, [:deck_id])
  end
end
