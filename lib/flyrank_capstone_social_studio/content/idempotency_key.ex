defmodule FlyrankCapstoneSocialStudio.Content.IdempotencyKey do
  use Ecto.Schema
  import Ecto.Changeset
  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "idempotency_keys" do
    field :key, :string
    field :request_path, :string
    field :response_payload, :map
    field :status, :string, default: "processing"

    timestamps()
  end

  @spec changeset(
          :invalid
          | %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: Ecto.Changeset.t()
  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, [:key, :request_path, :response_payload, :status])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
