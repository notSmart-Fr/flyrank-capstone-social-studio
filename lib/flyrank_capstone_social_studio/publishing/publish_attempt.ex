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
    publish_attempt
    |> cast(attrs, [:adapter_name, :status, :external_post_id, :response_payload, :error_message])
    |> validate_required([:adapter_name, :status, :external_post_id, :error_message])
  end
end
