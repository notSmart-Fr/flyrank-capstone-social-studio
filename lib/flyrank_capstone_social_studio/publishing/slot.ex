defmodule FlyrankCapstoneSocialStudio.Publishing.Slot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "slots" do
    field :scheduled_at, :utc_datetime
    field :status, :string, default: "pending"
    field :idempotency_key, :string

    belongs_to :variant, FlyrankCapstoneSocialStudio.Content.Variant

    timestamps()
  end

  @doc false
  def changeset(slot, attrs) do
    slot
    |> cast(attrs, [:scheduled_at, :status, :idempotency_key, :variant_id])
    |> validate_required([:scheduled_at, :status, :idempotency_key, :variant_id])
    |> validate_scheduled_at_in_future() # <--- Added custom validation
    |> foreign_key_constraint(:variant_id)
    |> unique_constraint(:idempotency_key)
  end

  # Validates that scheduled_at is at least in the present/future (with a small buffer)
  defp validate_scheduled_at_in_future(changeset) do
    validate_change(changeset, :scheduled_at, fn :scheduled_at, scheduled_at ->
      # 60-second buffer to allow for slight network/execution latency
      now = DateTime.utc_now() |> DateTime.add(-60, :second)

      if DateTime.compare(scheduled_at, now) == :gt do
        []
      else
        [scheduled_at: "must be in the future"]
      end
    end)
  end
end
