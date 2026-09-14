defmodule FlyrankCapstoneSocialStudio.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :title, :string
      add :source_type, :string
      add :content, :text
      add :url, :string
      add :external_source_id, :string

      timestamps(type: :utc_datetime)
    end
  end
end
