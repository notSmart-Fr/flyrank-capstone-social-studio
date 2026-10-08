defmodule FlyrankCapstoneSocialStudio.Publishing.Dispatcher do
  @moduledoc """
  Handles execution of publishing attempts with strict idempotency protection.
  """

  import Ecto.Query, warn: false
  alias FlyrankCapstoneSocialStudio.Repo
  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.Publishing.{Slot, PublishAttempt}
  alias FlyrankCapstoneSocialStudio.Content

  @spec dispatch_slot(FlyrankCapstoneSocialStudio.Publishing.Slot.t(), any()) ::
          {:error, any()} | {:ok, any()}
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

    # Railway-Oriented Publishing Guard Pipeline:
    # 1. Validate platform constraints defense-in-depth on variant schema
    # 2. Acquire pending publish attempt claim
    # 3. Dispatch to platform adapter
    with :ok <- Content.Variant.validate_platform_constraints(variant),
         {:ok, attempt} <- claim_publish_attempt(slot, adapter) do
      publish_with_adapter(adapter, slot, variant, attempt, opts)
    else
      {:error, {:constraint_violation, _}} = err ->
        err

      {:error, violations} when is_list(violations) ->
        handle_pre_publish_constraint_violation(slot, adapter, violations)

      {:error, %Ecto.Changeset{} = changeset} ->
        if Keyword.has_key?(changeset.errors, :slot_id) do
          {:error, :concurrent_request_in_flight}
        else
          {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp claim_publish_attempt(slot, adapter) do
    attempt_attrs = %{
      slot_id: slot.id,
      adapter_name: inspect(adapter),
      attempted_at: DateTime.utc_now(),
      status: "pending"
    }

    Publishing.create_publish_attempt(attempt_attrs)
  end

  defp handle_pre_publish_constraint_violation(slot, adapter, violations) do
    violation_msg = "Constraint violation at publish time: #{inspect(violations)}"

    # Record failed attempt directly for defense-in-depth audit trail
    Publishing.create_publish_attempt(%{
      slot_id: slot.id,
      adapter_name: inspect(adapter),
      attempted_at: DateTime.utc_now(),
      status: "failure",
      error_message: violation_msg
    })

    # Transition slot to failed status
    Publishing.update_slot(slot, %{status: "failed"})

    {:error, {:constraint_violation, violations}}
  end

  defp publish_with_adapter(adapter, slot, variant, attempt, opts) do
    case call_adapter_safely(adapter, variant.content, opts) do
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

      {:error, {:rate_limited, seconds}} ->
        {:ok, _updated_attempt} =
          Publishing.update_publish_attempt(attempt, %{
            status: "failure",
            error_message: "Rate limited. Retry after #{seconds}s"
          })

        {:error, {:rate_limited, seconds}}

      {:error, reason} ->
        error_str = if is_binary(reason), do: reason, else: inspect(reason)

        {:ok, updated_attempt} =
          Publishing.update_publish_attempt(attempt, %{
            status: "failure",
            error_message: error_str
          })

        Publishing.update_slot(slot, %{status: "failed"})

        {:error, updated_attempt}
    end
  end

  # Adapter crashes become ordinary failures so the pending claim is always
  # resolved and the slot can be retried.
  defp call_adapter_safely(adapter, content, opts) do
    adapter.publish(content, opts)
  rescue
    e -> {:error, "Adapter exception: #{Exception.message(e)}"}
  catch
    kind, value -> {:error, "Adapter #{kind}: #{inspect(value)}"}
  end
end
