defmodule FlyrankCapstoneSocialStudio.Publishing do
  @moduledoc """
  The Publishing domain context. Manages publication time slots, execution scheduling,
  idempotent adapter dispatching, and attempt audit history log retrieval.
  """

  import Ecto.Query, warn: false
  alias FlyrankCapstoneSocialStudio.Repo

  alias FlyrankCapstoneSocialStudio.Content.Variant
  alias FlyrankCapstoneSocialStudio.Publishing.PublishAttempt
  alias FlyrankCapstoneSocialStudio.Publishing.Slot
  alias FlyrankCapstoneSocialStudio.Publishing.Workers.PublishWorker

  # ===========================================================================
  # Scheduling & Oban Integration
  # ===========================================================================

  @doc """
  Schedules an approved variant into a publication slot and enqueues an Oban job.

  Returns `{:error, :unapproved_variant}` if the variant status is not `"approved"`.
  If a failed slot exists for this variant, it resets the slot to `"pending"` and re-enqueues it.
  """
def schedule_variant(%Variant{status: "approved"} = variant, attrs) do
  string_attrs =
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("variant_id", variant.id)

  idempotency_key = Map.get(string_attrs, "idempotency_key")

  # 1. If an explicit idempotency_key is provided, try creating the slot directly.
  # This lets Ecto's unique_constraint(:idempotency_key) catch duplicates and
  # return {:error, changeset} directly without entering the transaction.
  if idempotency_key do
    case create_slot(string_attrs) do
      {:ok, slot} ->
        enqueue_publish_job(slot)
        {:ok, slot}

      {:error, changeset} ->
        {:error, changeset}
    end
  else
    # 2. If no idempotency key was passed, handle normal transactional scheduling
    Repo.transaction(fn ->
      from(v in Variant, where: v.id == ^variant.id, lock: "FOR UPDATE")
      |> Repo.one!()

      case get_latest_variant_slot(variant.id) do
        %Slot{status: "failed"} = failed_slot ->
          {:ok, retry_slot} = update_slot(failed_slot, %{status: "pending", scheduled_at: DateTime.utc_now()})
          enqueue_publish_job(retry_slot)
          retry_slot

        nil ->
          case create_slot(string_attrs) do
            {:ok, slot} ->
              enqueue_publish_job(slot)
              slot

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        %Slot{} = existing_slot ->
          existing_slot
      end
    end)
  end
end

def schedule_variant(%Variant{}, _attrs) do
  {:error, :unapproved_variant}
end

  # ===========================================================================
  # Dispatching & Adapter Lookup
  # ===========================================================================

  @doc """
  Dispatches publication of a scheduled slot with idempotency guarantees.
  """
  def dispatch_slot(%Slot{} = slot, opts \\ []) do
    FlyrankCapstoneSocialStudio.Publishing.Dispatcher.dispatch_slot(slot, opts)
  end

  @doc """
  Returns the configured adapter module for a given platform string.
  Lookup is driven by Application configuration to allow runtime adapter swaps without code changes.
  """
  def adapter_for_platform(platform) when is_binary(platform) do
    adapters = Application.get_env(:flyrank_capstone_social_studio, :adapters, [])

    Keyword.get(
      adapters,
      String.to_atom(platform),
      FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX
    )
  end

  # ===========================================================================
  # Audit History Queries
  # ===========================================================================

  @doc """
  Lists all publish attempts with preloaded slots and variants for history audit logs.
  """
  def list_history do
    from(pa in PublishAttempt,
      order_by: [desc: pa.inserted_at],
      preload: [slot: :variant]
    )
    |> Repo.all()
  end

  # ===========================================================================
  # Slot CRUD Operations
  # ===========================================================================

  @doc """
  Returns the list of all scheduled slots.
  """
  def list_slots, do: Repo.all(Slot)

  @doc """
  Gets a single slot by ID. Raises `Ecto.NoResultsError` if not found.
  """
  def get_slot!(id), do: Repo.get!(Slot, id)

  @doc """
  Creates a new slot.
  """
  def create_slot(attrs) do
    %Slot{}
    |> Slot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing slot.
  """
  def update_slot(%Slot{} = slot, attrs) do
    slot
    |> Slot.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a slot.
  """
  def delete_slot(%Slot{} = slot), do: Repo.delete(slot)

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking slot changes.
  """
  def change_slot(%Slot{} = slot, attrs \\ %{}), do: Slot.changeset(slot, attrs)

  # ===========================================================================
  # PublishAttempt CRUD Operations
  # ===========================================================================

  @doc """
  Returns the list of all publish attempts.
  """
  def list_publish_attempts, do: Repo.all(PublishAttempt)

  @doc """
  Gets a single publish attempt by ID. Raises `Ecto.NoResultsError` if not found.
  """
  def get_publish_attempt!(id), do: Repo.get!(PublishAttempt, id)

  @doc """
  Creates a new publish attempt.
  """
  def create_publish_attempt(attrs) do
    %PublishAttempt{}
    |> PublishAttempt.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing publish attempt.
  """
  def update_publish_attempt(%PublishAttempt{} = publish_attempt, attrs) do
    publish_attempt
    |> PublishAttempt.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a publish attempt.
  """
  def delete_publish_attempt(%PublishAttempt{} = publish_attempt), do: Repo.delete(publish_attempt)

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking publish attempt changes.
  """
  def change_publish_attempt(%PublishAttempt{} = publish_attempt, attrs \\ %{}),
    do: PublishAttempt.changeset(publish_attempt, attrs)

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp get_latest_variant_slot(variant_id) do
    from(s in Slot, where: s.variant_id == ^variant_id, order_by: [desc: s.inserted_at], limit: 1)
    |> Repo.one()
  end

  defp enqueue_publish_job(%Slot{} = slot) do
    scheduled_at = slot.scheduled_at || DateTime.utc_now()

    %{slot_id: slot.id}
    |> PublishWorker.new(scheduled_at: scheduled_at)
    |> Oban.insert!()
  end
end
