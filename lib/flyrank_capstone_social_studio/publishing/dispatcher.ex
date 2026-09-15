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
  Executes publishing for a slot. Idempotent: safe against retries and duplicate calls.
  """
  def dispatch_slot(%Slot{} = slot, opts \\ []) do
    # 1. Idempotency Check: Check for existing successful attempt
    existing_successful =
      from(pa in PublishAttempt,
        where: pa.slot_id == ^slot.id and pa.status == "success"
      )
      |> Repo.one()

    if existing_successful do
      {:ok, existing_successful}
    else
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
            raw_response: response
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
