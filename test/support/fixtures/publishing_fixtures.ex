defmodule FlyrankCapstoneSocialStudio.PublishingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FlyrankCapstoneSocialStudio.Publishing` context.
  """

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
    {:ok, slot} =
      attrs
      |> Enum.into(%{
        idempotency_key: "some idempotency_key",
        scheduled_at: ~U[2026-09-13 05:47:00Z],
        status: "some status"
      })
      |> FlyrankCapstoneSocialStudio.Publishing.create_slot()

    slot
  end
end
