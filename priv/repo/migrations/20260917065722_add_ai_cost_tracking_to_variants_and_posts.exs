defmodule FlyrankCapstoneSocialStudio.Repo.Migrations.AddAiCostTrackingToVariantsAndPosts do
  use Ecto.Migration

  def change do
    alter table(:variants) do
      add :prompt_tokens, :integer, default: 0
      add :completion_tokens, :integer, default: 0
      add :total_tokens, :integer, default: 0
      add :generation_cost, :decimal, precision: 12, scale: 6, default: 0.0
      add :model_used, :string
    end

    alter table(:posts) do
      add :total_ai_cost, :decimal, precision: 12, scale: 6, default: 0.0
    end
  end
end
