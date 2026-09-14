defmodule FlyrankCapstoneSocialStudio.Content.Variant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "variants" do
    field :platform, :string
    field :content, :string
    field :status, :string
    field :hashtags_count, :integer
    field :character_count, :integer
    field :rejection_reason, :string
    field :post_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, [:platform, :content, :status, :hashtags_count, :character_count, :rejection_reason])
    |> validate_required([:platform, :content, :status, :hashtags_count, :character_count, :rejection_reason])
  end
end
