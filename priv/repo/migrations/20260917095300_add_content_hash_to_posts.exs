defmodule FlyrankCapstoneSocialStudio.Repo.Migrations.AddContentHashToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :content_hash, :string
    end

    # Index for fast deduplication lookups in ingest_and_generate/2
    create index(:posts, [:content_hash])

    # Enforce database-level uniqueness for external integrations (ignoring NULLs)
    create unique_index(:posts, [:external_source_id], where: "external_source_id IS NOT NULL")
  end
end
