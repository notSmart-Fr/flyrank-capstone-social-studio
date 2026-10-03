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

  @doc """
  Builds a changeset for an `IdempotencyKey`.

  Ensures `:key` and `:status` are present and enforces a unique constraint on `:key`.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, [:key, :request_path, :response_payload, :status])
    |> validate_required([:key, :status])
    |> validate_inclusion(:status, ["processing", "completed", "failed"])
    |> unique_constraint(:key)
  end
end
