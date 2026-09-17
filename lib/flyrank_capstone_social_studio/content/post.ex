defmodule FlyrankCapstoneSocialStudio.Content.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :source_type, :string
    field :content, :string
    field :url, :string
    field :external_source_id, :string
    # Total aggregated campaign cost
    field :total_ai_cost, :decimal, default: Decimal.new("0.0")
    has_many :variants, FlyrankCapstoneSocialStudio.Content.Variant

    timestamps()
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :source_type, :content, :url, :external_source_id])
    # Keep url and external_source_id optional
    |> validate_required([:title, :source_type, :content])
    |> validate_inclusion(:source_type, ["url", "markdown"])
  end
end
