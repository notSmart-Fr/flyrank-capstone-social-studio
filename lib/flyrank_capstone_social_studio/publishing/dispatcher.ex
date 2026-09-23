defmodule FlyrankCapstoneSocialStudio.Publishing.Dispatcher do
  @moduledoc """
  Handles execution of publishing attempts with strict idempotency protection.
  """

  import Ecto.Query, warn: false
  alias FlyrankCapstoneSocialStudio.Repo
  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.Publishing.{Slot, PublishAttempt}
  alias FlyrankCapstoneSocialStudio.Content

  @doc """
  Short-circuits immediately if the slot is already published to enforce idempotency.
  """
  def dispatch_slot(slot, opts \\ [])

  def dispatch_slot(%Slot{status: "published"} = _slot, _opts) do
    {:ok, %{status: :already_published}}
  end

  def dispatch_slot(%Slot{} = slot, opts) do
    # Look up existing successful publish attempt for this slot
    existing_successful =
      from(pa in PublishAttempt,
        where: pa.slot_id == ^slot.id and pa.status == "success"
      )
      |> Repo.one()

    cond do
      existing_successful ->
        {:ok, existing_successful}

      slot.status == "published" ->
        # Fallback if slot is marked published but attempt wasn't pre-loaded
        {:ok, Repo.get_by(PublishAttempt, slot_id: slot.id, status: "success")}

      true ->
        execute_dispatch(slot, opts)
    end
  end

  defp execute_dispatch(%Slot{} = slot, opts) do
    # Preload variant to get content and platform
    slot = Repo.preload(slot, :variant)
    variant = slot.variant

    adapter = Publishing.adapter_for_platform(variant.platform)

    attempt_attrs = %{
      slot_id: slot.id,
      adapter_name: inspect(adapter),
      attempted_at: DateTime.utc_now(),
      status: "pending"
    }

    {:ok, attempt} = Publishing.create_publish_attempt(attempt_attrs)

    case adapter.publish(variant.content, opts) do
      {:ok, %{external_id: ext_id, raw_response: response}} ->
        {:ok, updated_attempt} =
          Publishing.update_publish_attempt(attempt, %{
            status: "success",
            external_post_id: ext_id,
            response_payload: %{raw_response: response}
          })

        # Mark slot and variant as published
        Publishing.update_slot(slot, %{status: "published"})
        Content.update_variant(variant, %{status: "published"})

        {:ok, updated_attempt}

      {:error, reason} ->
        {:ok, updated_attempt} =
          Publishing.update_publish_attempt(attempt, %{
            status: "failure",
            error_message: reason
          })

        Publishing.update_slot(slot, %{status: "failed"})

        {:error, updated_attempt}
    end
  end
end
