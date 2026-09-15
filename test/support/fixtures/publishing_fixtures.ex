defmodule FlyrankCapstoneSocialStudio.PublishingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FlyrankCapstoneSocialStudio.Publishing` context.
  """

  import FlyrankCapstoneSocialStudio.ContentFixtures

  @doc """
  Generate a publish_attempt.
  """
  def publish_attempt_fixture(attrs \\ %{}) do
    {:ok, publish_attempt} =
      attrs
      |> Enum.into(%{
        adapter_name: "some adapter_name",
        error_message: "some error_message",
        external_post_id: "some external_post_id",
        response_payload: %{},
        status: "some status"
      })
      |> FlyrankCapstoneSocialStudio.Publishing.create_publish_attempt()

    publish_attempt
  end

  @doc """
  Generate a slot.
  """
  def slot_fixture(attrs \\ %{}) do
    variant_id =
      case Map.get(attrs, :variant_id) || Map.get(attrs, "variant_id") do
        nil -> variant_fixture().id
        id -> id
      end

    {:ok, slot} =
      attrs
      |> Enum.into(%{
        idempotency_key: "some idempotency_key #{System.unique_integer([:positive])}",
        scheduled_at: ~U[2026-09-13 05:47:00Z],
        status: "some status",
        variant_id: variant_id
      })
      |> FlyrankCapstoneSocialStudio.Publishing.create_slot()

    slot
  end
end
