defmodule FlyrankCapstoneSocialStudio.Content.Post do
  use Ecto.Schema
  import Ecto.Changeset
  # Add this type definition for Dialyzer / ElixirLS:
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

  @spec changeset(
          {map(),
           %{
             optional(atom()) =>
               atom()
               | {:array | :assoc | :embed | :in | :map | :parameterized | :supertype | :try,
                  any()}
           }}
          | %{
              :__struct__ => atom() | %{:__changeset__ => any(), optional(any()) => any()},
              optional(atom()) => any()
            },
          :invalid | %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: Ecto.Changeset.t()
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :source_type, :content, :url, :external_source_id])
    |> validate_required([:title, :source_type, :content])
    |> validate_inclusion(:source_type, ["url", "markdown"])
  end
end
