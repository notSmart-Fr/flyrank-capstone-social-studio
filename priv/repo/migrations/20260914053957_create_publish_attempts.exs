defmodule FlyrankCapstoneSocialStudio.Repo.Migrations.CreatePublishAttempts do
  use Ecto.Migration

  def change do
    create table(:publish_attempts) do
      add :adapter_name, :string
      add :status, :string
      add :external_post_id, :string
      add :response_payload, :map
      add :error_message, :text
      add :slot_id, references(:slots, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:publish_attempts, [:slot_id])
  end
end
