defmodule FlyrankCapstoneSocialStudio.Publishing.PublishAttempt do
  use Ecto.Schema
  import Ecto.Changeset
  @type t :: %__MODULE__{}
  schema "publish_attempts" do
    field :adapter_name, :string
    field :status, :string
    field :external_post_id, :string
    field :response_payload, :map
    field :error_message, :string
    belongs_to :slot, FlyrankCapstoneSocialStudio.Publishing.Slot

    timestamps(type: :utc_datetime)
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
          %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: Ecto.Changeset.t()
  @doc false
  def changeset(publish_attempt, attrs) do
    changeset =
      publish_attempt
      |> cast(attrs, [
        :adapter_name,
        :status,
        :external_post_id,
        :response_payload,
        :error_message
      ])
      |> put_change(:slot_id, Map.get(attrs, :slot_id, publish_attempt.slot_id))
      |> validate_required([:adapter_name, :status])

    case get_field(changeset, :status) do
      "success" -> validate_required(changeset, [:external_post_id])
      "failure" -> validate_required(changeset, [:error_message])
      _ -> changeset
    end
  end
end
