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
  """
  def schedule_variant(%Variant{status: "approved"} = variant, attrs) do
    string_attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("variant_id", variant.id)

    %Slot{}
    |> Slot.changeset(string_attrs)
    |> Repo.insert()
  end

  def schedule_variant(%Variant{} = _variant, _attrs) do
    {:error, :unapproved_variant}
  end
end
