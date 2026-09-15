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
    |> foreign_key_constraint(:variant_id)
    |> unique_constraint(:idempotency_key)
  end
end
