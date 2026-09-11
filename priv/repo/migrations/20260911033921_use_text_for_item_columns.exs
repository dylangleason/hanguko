defmodule Hanguko.Repo.Migrations.UseTextForItemColumns do
  use Ecto.Migration

  # varchar(255) is an arbitrary limit for content such as example sentences;
  # in Postgres text has the same storage and performance. Changing
  # varchar -> text is a catalog-only change (no table rewrite).
  def change do
    alter table(:items) do
      modify :source_key, :text, from: :string
      modify :korean, :text, from: :string
      modify :romanization, :text, from: :string
      modify :meaning, :text, from: :string
      modify :part_of_speech, :text, from: :string
    end
  end
end
