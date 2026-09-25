defmodule FlyrankCapstoneSocialStudio.Publishing do
  @moduledoc """
  The Publishing domain context. Manages publication time slots, execution scheduling,
  idempotent adapter dispatching, and attempt audit history log retrieval.
  """

  import Ecto.Query, warn: false
  alias FlyrankCapstoneSocialStudio.Repo

  alias FlyrankCapstoneSocialStudio.Content.Variant
  alias FlyrankCapstoneSocialStudio.Publishing.PublishAttempt
  alias FlyrankCapstoneSocialStudio.Publishing.{PublishAttempt, Slot}
  alias FlyrankCapstoneSocialStudio.Publishing.Workers.PublishWorker

  # ===========================================================================
  # Scheduling & Oban Integration
  # ===========================================================================

  @spec schedule_variant(FlyrankCapstoneSocialStudio.Content.Variant.t(), any()) :: any()
  @doc """
  Schedules an approved variant into a publication slot and enqueues its dispatch job.

  ## Options

    * `:mode` - Specifies the scheduling calculation mode.
      * `:manual` (default) - Uses explicit `"scheduled_at"` timestamp in `attrs`
        (falling back to `DateTime.utc_now/0`).
      * `:auto` - Automatically calculates the next optimal time gap for the variant's platform.

  ## Behaviors & Guarantees

    * **Idempotency Check:** When `idempotency_key` is present in `attrs`, attempts direct insertion.
      Returns `{:error, changeset}` on conflict.
    * **Concurrency Lock:** When no `idempotency_key` is provided, executes inside a transaction with
      a `FOR UPDATE` lock on the `%Variant{}` row to prevent race conditions.
    * **Retry Handling:** Re-uses existing `%Slot{status: "failed"}` records by resetting status to
      `"pending"`, updating `scheduled_at`, and re-enqueueing the Oban job.

  ## Return Values

    * `{:ok, %Slot{}}` - Successfully created or updated slot.
    * `{:error, %Ecto.Changeset{}}` - Validation failure or duplicate `idempotency_key`.
    * `{:error, :unapproved_variant}` - Returned if `%Variant{status: status}` is not `"approved"`.
  """
  def schedule_variant(variant, attrs, opts \\ [])

  def schedule_variant(%Variant{status: "approved"} = variant, attrs, opts) do
    mode = Keyword.get(opts, :mode, :manual)
    scheduled_at = resolve_scheduled_at(mode, variant.platform, attrs)

    # 1. Resolve or generate an idempotency key fallback
    raw_key = Map.get(attrs, :idempotency_key) || Map.get(attrs, "idempotency_key")
    idempotency_key = raw_key || "slot_#{variant.id}_#{System.system_time(:microsecond)}"

    string_attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("variant_id", variant.id)
      |> Map.put("scheduled_at", scheduled_at)
      # 👈 Guarantees key presence
      |> Map.put("idempotency_key", idempotency_key)

    # 2. If caller provided an explicit idempotency key, execute direct path
    if raw_key do
      case create_slot(string_attrs) do
        {:ok, slot} ->
          maybe_enqueue_publish_job(slot, opts)
          {:ok, slot}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      # 3. Automatic fallback path: uses generated key in transaction
      Repo.transaction(fn ->
        lock_variant_row(variant.id)

        case get_latest_variant_slot(variant.id) do
          %Slot{status: "failed"} = failed_slot ->
            {:ok, retry_slot} =
              update_slot(failed_slot, %{status: "pending", scheduled_at: scheduled_at})

            maybe_enqueue_publish_job(retry_slot, opts)
            retry_slot

          nil ->
            case create_slot(string_attrs) do
              {:ok, slot} ->
                maybe_enqueue_publish_job(slot, opts)
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

  def schedule_variant(%Variant{}, _attrs, _opts) do
    {:error, :unapproved_variant}
  end

  defp maybe_enqueue_publish_job(slot, opts) do
    if Keyword.get(opts, :enqueue, true) do
      enqueue_publish_job(slot)
    end

    :ok
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

  @spec list_history() :: any()
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

  @spec list_slots() :: any()
  def list_slots, do: Repo.all(Slot)
  def get_slot!(id), do: Repo.get!(Slot, id)

  @spec create_slot(
          :invalid
          | %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: any()
  def create_slot(attrs) do
    %Slot{}
    |> Slot.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_slot(
          FlyrankCapstoneSocialStudio.Publishing.Slot.t(),
          :invalid | %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: any()
  def update_slot(%Slot{} = slot, attrs) do
    slot
    |> Slot.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_slot(FlyrankCapstoneSocialStudio.Publishing.Slot.t()) :: any()
  def delete_slot(%Slot{} = slot), do: Repo.delete(slot)
  def change_slot(%Slot{} = slot, attrs \\ %{}), do: Slot.changeset(slot, attrs)

  # ===========================================================================
  # PublishAttempt CRUD Operations
  # ===========================================================================

  def list_publish_attempts, do: Repo.all(PublishAttempt)
  def get_publish_attempt!(id), do: Repo.get!(PublishAttempt, id)

  def create_publish_attempt(attrs) do
    %PublishAttempt{}
    |> PublishAttempt.changeset(attrs)
    |> Repo.insert()
  end

  def update_publish_attempt(%PublishAttempt{} = publish_attempt, attrs) do
    publish_attempt
    |> PublishAttempt.changeset(attrs)
    |> Repo.update()
  end

  def delete_publish_attempt(%PublishAttempt{} = publish_attempt),
    do: Repo.delete(publish_attempt)

  def change_publish_attempt(%PublishAttempt{} = publish_attempt, attrs \\ %{}),
    do: PublishAttempt.changeset(publish_attempt, attrs)

  # ===========================================================================
  # Private Helpers (Extracted Query & Business Calculation Logic)
  # ===========================================================================

  # Calculates schedule target timestamp based on mode
  defp resolve_scheduled_at(:manual, _platform, attrs) do
    Map.get(attrs, "scheduled_at") || Map.get(attrs, :scheduled_at) || DateTime.utc_now()
  end

  defp resolve_scheduled_at(:auto, platform, _attrs) do
    latest_slot_time = get_latest_platform_slot_time(platform)
    now = DateTime.utc_now()

    cond do
      is_nil(latest_slot_time) ->
        DateTime.add(now, 15 * 60, :second)

      DateTime.compare(latest_slot_time, now) == :gt ->
        DateTime.add(latest_slot_time, 2 * 3600, :second)

      true ->
        DateTime.add(now, 15 * 60, :second)
    end
  end

  # Locks a variant row for pessimistic concurrency control
  defp lock_variant_row(variant_id) do
    from(v in Variant, where: v.id == ^variant_id, lock: "FOR UPDATE")
    |> Repo.one!()
  end

  # Finds the latest slot created for a given variant
  defp get_latest_variant_slot(variant_id) do
    from(s in Slot, where: s.variant_id == ^variant_id, order_by: [desc: s.inserted_at], limit: 1)
    |> Repo.one()
  end

  # Finds the latest pending/published slot scheduled_at timestamp for a platform
  defp get_latest_platform_slot_time(platform) do
    from(s in Slot,
      join: v in assoc(s, :variant),
      where: v.platform == ^platform and s.status in ["pending", "published"],
      select: max(s.scheduled_at)
    )
    |> Repo.one()
  end

  # Enqueues the Oban job for dispatching
  defp enqueue_publish_job(%Slot{} = slot) do
    scheduled_at = slot.scheduled_at || DateTime.utc_now()

    %{slot_id: slot.id}
    |> PublishWorker.new(scheduled_at: scheduled_at)
    |> Oban.insert!()
  end
end
