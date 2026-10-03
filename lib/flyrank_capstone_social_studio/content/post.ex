defmodule FlyrankCapstoneSocialStudio.Content.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "posts" do
    field :title, :string
    field :source_type, :string
    field :content, :string
    field :url, :string
    field :external_source_id, :string
    field :total_ai_cost, :decimal, default: Decimal.new("0.0")

    has_many :variants, FlyrankCapstoneSocialStudio.Content.Variant
    has_many :ai_generations, FlyrankCapstoneSocialStudio.Content.AiGeneration
    timestamps()
  end

  # Clean, standard Ecto typespec for Dialyzer
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :source_type, :content, :url, :external_source_id])
    |> validate_required([:title, :source_type, :content])
    |> validate_inclusion(:source_type, ["url", "markdown"])
  end
end
