defmodule FlyrankCapstoneSocialStudio.Content.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :source_type, :string
    field :content, :string
    field :url, :string
    field :external_source_id, :string
    # <--- Added field
    field :content_hash, :string
    field :total_ai_cost, :decimal, default: Decimal.new("0.0")

    has_many :variants, FlyrankCapstoneSocialStudio.Content.Variant
    has_many :ai_generations, FlyrankCapstoneSocialStudio.Content.AiGeneration
    timestamps()
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :source_type, :content, :url, :external_source_id, :content_hash])
    |> validate_required([:title, :source_type, :content])
    |> validate_inclusion(:source_type, ["url", "markdown"])
    |> put_content_hash()
  end

  defp put_content_hash(changeset) do
    case get_change(changeset, :content) || get_field(changeset, :content) do
      nil ->
        changeset

      content ->
        title = get_field(changeset, :title) || ""
        hash = :crypto.hash(:sha256, "#{title}:#{content}") |> Base.encode16()
        put_change(changeset, :content_hash, hash)
    end
  end
end
