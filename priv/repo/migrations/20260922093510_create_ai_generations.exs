defmodule FlyrankCapstoneSocialStudio.Repo.Migrations.CreateAiGenerations do
  use Ecto.Migration

  def change do
    create table(:ai_generations) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :platform, :string, null: false
      add :model_used, :string
      add :prompt_tokens, :integer, default: 0
      add :completion_tokens, :integer, default: 0
      add :total_tokens, :integer, default: 0
      add :cost, :decimal, precision: 12, scale: 6, default: 0.0

      timestamps()
    end

    create index(:ai_generations, [:post_id])
  end
end
