defmodule FlyrankCapstoneSocialStudio.Publishing.Slot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "slots" do
    field :scheduled_at, :utc_datetime
    field :status, :string
    field :idempotency_key, :string
    field :variant_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(slot, attrs) do
    slot
    |> cast(attrs, [:scheduled_at, :status, :idempotency_key])
    |> validate_required([:scheduled_at, :status, :idempotency_key])
  end
end
