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
    field :content_hash, :string

    has_many :variants, FlyrankCapstoneSocialStudio.Content.Variant
    has_many :ai_generations, FlyrankCapstoneSocialStudio.Content.AiGeneration
    timestamps()
  end

  # Clean, standard Ecto typespec for Dialyzer
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :source_type, :content, :url, :external_source_id, :content_hash])
    |> validate_required([:title, :source_type, :content])
    |> validate_inclusion(:source_type, ["url", "markdown"])
    |> maybe_generate_content_hash()
  end

  defp maybe_generate_content_hash(changeset) do
    case get_change(changeset, :content) do
      content when is_binary(content) ->
        hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        put_change(changeset, :content_hash, hash)

      _ ->
        changeset
    end
  end
end
