defmodule FlyrankCapstoneSocialStudio.Content.AiGeneration do
  use Ecto.Schema
  import Ecto.Changeset
  @type t :: %__MODULE__{}
  schema "ai_generations" do
    field :platform, :string
    field :model_used, :string
    field :prompt_tokens, :integer, default: 0
    field :completion_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :cost, :decimal, default: Decimal.new("0.0")

    belongs_to :post, FlyrankCapstoneSocialStudio.Content.Post

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
  def changeset(ai_generation, attrs) do
    ai_generation
    |> cast(attrs, [
      :post_id,
      :platform,
      :model_used,
      :prompt_tokens,
      :completion_tokens,
      :total_tokens,
      :cost
    ])
    |> validate_required([:post_id, :platform])
  end
end
