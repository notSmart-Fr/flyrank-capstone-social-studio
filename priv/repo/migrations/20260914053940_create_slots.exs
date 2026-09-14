defmodule FlyrankCapstoneSocialStudio.Repo.Migrations.CreateSlots do
  use Ecto.Migration

  def change do
    create table(:slots) do
      add :scheduled_at, :utc_datetime
      add :status, :string
      add :idempotency_key, :string
      add :variant_id, references(:variants, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:slots, [:variant_id])
    # Enforce database-level uniqueness for idempotency keys
    create unique_index(:slots, [:idempotency_key])
  end
end
