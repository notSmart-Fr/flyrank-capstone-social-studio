defmodule FlyrankCapstoneSocialStudio.Content.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :source_type, :string
    field :content, :string
    field :url, :string
    field :external_source_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :source_type, :content, :url, :external_source_id])
    |> validate_required([:title, :source_type, :content, :url, :external_source_id])
  end
end
