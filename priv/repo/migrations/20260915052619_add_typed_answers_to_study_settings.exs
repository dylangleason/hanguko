defmodule Hanguko.Repo.Migrations.AddTypedAnswersToStudySettings do
  use Ecto.Migration

  def change do
    alter table(:study_settings) do
      add :typed_answers, :boolean, null: false, default: false
    end
  end
end
