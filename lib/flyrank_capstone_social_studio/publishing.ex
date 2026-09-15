defmodule FlyrankCapstoneSocialStudio.Publishing do
  @moduledoc """
  The Publishing context.
  """

  import Ecto.Query, warn: false
  alias FlyrankCapstoneSocialStudio.Content.Variant
  alias FlyrankCapstoneSocialStudio.Publishing.PublishAttempt
  alias FlyrankCapstoneSocialStudio.Publishing.Slot
  alias FlyrankCapstoneSocialStudio.Repo

  @doc """
  Returns the list of publish_attempts.

  ## Examples

      iex> list_publish_attempts()
      [%PublishAttempt{}, ...]

  """
  def list_publish_attempts do
    Repo.all(PublishAttempt)
  end

  @doc """
  Gets a single publish_attempt.

  Raises `Ecto.NoResultsError` if the Publish attempt does not exist.

  ## Examples

      iex> get_publish_attempt!(123)
      %PublishAttempt{}

      iex> get_publish_attempt!(456)
      ** (Ecto.NoResultsError)

  """
  def get_publish_attempt!(id), do: Repo.get!(PublishAttempt, id)

  @doc """
  Creates a publish_attempt.

  ## Examples

      iex> create_publish_attempt(%{field: value})
      {:ok, %PublishAttempt{}}

      iex> create_publish_attempt(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_publish_attempt(attrs) do
    %PublishAttempt{}
    |> PublishAttempt.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a publish_attempt.

  ## Examples

      iex> update_publish_attempt(publish_attempt, %{field: new_value})
      {:ok, %PublishAttempt{}}

      iex> update_publish_attempt(publish_attempt, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_publish_attempt(%PublishAttempt{} = publish_attempt, attrs) do
    publish_attempt
    |> PublishAttempt.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a publish_attempt.

  ## Examples

      iex> delete_publish_attempt(publish_attempt)
      {:ok, %PublishAttempt{}}

      iex> delete_publish_attempt(publish_attempt)
      {:error, %Ecto.Changeset{}}

  """
  def delete_publish_attempt(%PublishAttempt{} = publish_attempt) do
    Repo.delete(publish_attempt)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking publish_attempt changes.

  ## Examples

      iex> change_publish_attempt(publish_attempt)
      %Ecto.Changeset{data: %PublishAttempt{}}

  """
  def change_publish_attempt(%PublishAttempt{} = publish_attempt, attrs \\ %{}) do
    PublishAttempt.changeset(publish_attempt, attrs)
  end

  @doc """
  Returns the list of slots.

  ## Examples

      iex> list_slots()
      [%Slot{}, ...]

  """
  def list_slots do
    Repo.all(Slot)
  end

  @doc """
  Gets a single slot.

  Raises `Ecto.NoResultsError` if the Slot does not exist.

  ## Examples

      iex> get_slot!(123)
      %Slot{}

      iex> get_slot!(456)
      ** (Ecto.NoResultsError)

  """
  def get_slot!(id), do: Repo.get!(Slot, id)

  @doc """
  Creates a slot.

  ## Examples

      iex> create_slot(%{field: value})
      {:ok, %Slot{}}

      iex> create_slot(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_slot(attrs) do
    %Slot{}
    |> Slot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a slot.

  ## Examples

      iex> update_slot(slot, %{field: new_value})
      {:ok, %Slot{}}

      iex> update_slot(slot, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_slot(%Slot{} = slot, attrs) do
    slot
    |> Slot.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a slot.

  ## Examples

      iex> delete_slot(slot)
      {:ok, %Slot{}}

      iex> delete_slot(slot)
      {:error, %Ecto.Changeset{}}

  """
  def delete_slot(%Slot{} = slot) do
    Repo.delete(slot)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking slot changes.

  ## Examples

      iex> change_slot(slot)
      %Ecto.Changeset{data: %Slot{}}

  """
  def change_slot(%Slot{} = slot, attrs \\ %{}) do
    Slot.changeset(slot, attrs)
  end

 @doc """
  Schedules a variant. Refuses with an error tuple if the variant is not approved.
  Enqueues a durable Oban job for execution.
  """
  def schedule_variant(%Variant{status: "approved"} = variant, attrs) do
    string_attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("variant_id", variant.id)

    Repo.transaction(fn ->
      from(v in Variant, where: v.id == ^variant.id, lock: "FOR UPDATE")
      |> Repo.one!()

      case Repo.one(from(s in Slot, where: s.variant_id == ^variant.id, order_by: [desc: s.inserted_at], limit: 1)) do
        %Slot{status: "failed"} = failed_slot ->
          {:ok, retry_slot} = update_slot(failed_slot, %{status: "pending", scheduled_at: DateTime.utc_now()})
          enqueue_publish_job(retry_slot)
          retry_slot

        %Slot{} = existing_slot ->
          existing_slot

        nil ->
          case %Slot{} |> Slot.changeset(string_attrs) |> Repo.insert() do
            {:ok, slot} ->
              enqueue_publish_job(slot)

              slot

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
      end
    end)
  end

  def schedule_variant(%Variant{} = _variant, _attrs) do
    {:error, :unapproved_variant}
  end

  defp enqueue_publish_job(slot) do
    scheduled_at = slot.scheduled_at || DateTime.utc_now()

    %{slot_id: slot.id}
    |> FlyrankCapstoneSocialStudio.Publishing.Workers.PublishWorker.new(scheduled_at: scheduled_at)
    |> Oban.insert!()
  end

  @doc """
  Returns the adapter module associated with a platform string.
  """
  def adapter_for_platform("telegram"),
    do: FlyrankCapstoneSocialStudio.Publishing.Adapters.Telegram

  def adapter_for_platform("mock_x"), do: FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX

  def adapter_for_platform("mock_linkedin"),
    do: FlyrankCapstoneSocialStudio.Publishing.Adapters.MockLinkedIn

  def adapter_for_platform(_), do: FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX

  @doc """
  Dispatches publication of a scheduled slot with idempotency guarantees.
  """
  def dispatch_slot(slot, opts \\ []) do
    FlyrankCapstoneSocialStudio.Publishing.Dispatcher.dispatch_slot(slot, opts)
  end
  @doc """
  Lists all publish attempts with their associated slot and variant preloaded for audit logs.
  """
  def list_history do
    from(pa in PublishAttempt,
      order_by: [desc: pa.inserted_at],
      preload: [slot: :variant]
    )
    |> Repo.all()
  end
end
