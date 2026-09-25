defmodule FlyrankCapstoneSocialStudio.Repo.Migrations.AddIdempotencyKeysTable do
  use Ecto.Migration

  def change do
    create table(:idempotency_keys, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :key, :string, null: false
      add :request_path, :string
      # Stores the cached {post, variants} JSON output
      add :response_payload, :map
      # "processing" | "completed"
      add :status, :string, default: "processing"

      timestamps()
    end

    create unique_index(:idempotency_keys, [:key])
  end
end
