defmodule FlyrankCapstoneSocialStudio.Repo.Migrations.AddActiveAttemptUniqueIndexToPublishAttempts do
  use Ecto.Migration

  # At most one in-flight or successful attempt per slot. Failed attempts are
  # excluded so a failed slot can still be retried.
  def change do
    create unique_index(:publish_attempts, [:slot_id],
             where: "status IN ('pending', 'success')",
             name: :publish_attempts_active_slot_index
           )
  end
end
