defmodule FlyrankCapstoneSocialStudio.Repo.Migrations.CreateVariants do
  use Ecto.Migration

  def change do
    create table(:variants) do
      add :platform, :string
      add :content, :text
      add :status, :string
      add :hashtags_count, :integer
      add :character_count, :integer
      add :rejection_reason, :text
      add :post_id, references(:posts, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:variants, [:post_id])
  end
end
