defmodule FlyrankCapstoneSocialStudio.Publishing.PublishAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "publish_attempts" do
    field :adapter_name, :string
    field :status, :string
    field :external_post_id, :string
    field :response_payload, :map
    field :error_message, :string
    field :slot_id, :id

    timestamps(type: :utc_datetime)
  end

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
