defmodule FlyrankCapstoneSocialStudio.PublishingTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Publishing

  describe "publish_attempts" do
    alias FlyrankCapstoneSocialStudio.Publishing.PublishAttempt

    import FlyrankCapstoneSocialStudio.PublishingFixtures

    @invalid_attrs %{
      status: nil,
      adapter_name: nil,
      external_post_id: nil,
      response_payload: nil,
      error_message: nil
    }

    test "list_publish_attempts/0 returns all publish_attempts" do
      publish_attempt = publish_attempt_fixture()
      assert Publishing.list_publish_attempts() == [publish_attempt]
    end

    test "get_publish_attempt!/1 returns the publish_attempt with given id" do
      publish_attempt = publish_attempt_fixture()
      assert Publishing.get_publish_attempt!(publish_attempt.id) == publish_attempt
    end

    test "create_publish_attempt/1 with valid data creates a publish_attempt" do
      valid_attrs = %{
        status: "some status",
        adapter_name: "some adapter_name",
        external_post_id: "some external_post_id",
        response_payload: %{},
        error_message: "some error_message"
      }

      assert {:ok, %PublishAttempt{} = publish_attempt} =
               Publishing.create_publish_attempt(valid_attrs)

      assert publish_attempt.status == "some status"
      assert publish_attempt.adapter_name == "some adapter_name"
      assert publish_attempt.external_post_id == "some external_post_id"
      assert publish_attempt.response_payload == %{}
      assert publish_attempt.error_message == "some error_message"
    end

    test "create_publish_attempt/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Publishing.create_publish_attempt(@invalid_attrs)
    end

    test "update_publish_attempt/2 with valid data updates the publish_attempt" do
      publish_attempt = publish_attempt_fixture()

      update_attrs = %{
        status: "some updated status",
        adapter_name: "some updated adapter_name",
        external_post_id: "some updated external_post_id",
        response_payload: %{},
        error_message: "some updated error_message"
      }

      assert {:ok, %PublishAttempt{} = publish_attempt} =
               Publishing.update_publish_attempt(publish_attempt, update_attrs)

      assert publish_attempt.status == "some updated status"
      assert publish_attempt.adapter_name == "some updated adapter_name"
      assert publish_attempt.external_post_id == "some updated external_post_id"
      assert publish_attempt.response_payload == %{}
      assert publish_attempt.error_message == "some updated error_message"
    end

    test "update_publish_attempt/2 with invalid data returns error changeset" do
      publish_attempt = publish_attempt_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Publishing.update_publish_attempt(publish_attempt, @invalid_attrs)

      assert publish_attempt == Publishing.get_publish_attempt!(publish_attempt.id)
    end

    test "delete_publish_attempt/1 deletes the publish_attempt" do
      publish_attempt = publish_attempt_fixture()
      assert {:ok, %PublishAttempt{}} = Publishing.delete_publish_attempt(publish_attempt)

      assert_raise Ecto.NoResultsError, fn ->
        Publishing.get_publish_attempt!(publish_attempt.id)
      end
    end

    test "change_publish_attempt/1 returns a publish_attempt changeset" do
      publish_attempt = publish_attempt_fixture()
      assert %Ecto.Changeset{} = Publishing.change_publish_attempt(publish_attempt)
    end
  end

  describe "slots" do
    alias FlyrankCapstoneSocialStudio.Publishing.Slot

    import FlyrankCapstoneSocialStudio.PublishingFixtures
    import FlyrankCapstoneSocialStudio.ContentFixtures

    @invalid_attrs %{status: nil, scheduled_at: nil, idempotency_key: nil, variant_id: nil}

    test "list_slots/0 returns all slots" do
      slot = slot_fixture()
      assert Publishing.list_slots() == [slot]
    end

    test "get_slot!/1 returns the slot with given id" do
      slot = slot_fixture()
      assert Publishing.get_slot!(slot.id) == slot
    end

    test "create_slot/1 with valid data creates a slot" do
      variant = variant_fixture()

      valid_attrs = %{
        status: "some status",
        scheduled_at: ~U[2026-09-13 05:47:00Z],
        idempotency_key: "some idempotency_key",
        variant_id: variant.id
      }

      assert {:ok, %Slot{} = slot} = Publishing.create_slot(valid_attrs)
      assert slot.status == "some status"
      assert slot.scheduled_at == ~U[2026-09-13 05:47:00Z]
      assert slot.idempotency_key == "some idempotency_key"
      assert slot.variant_id == variant.id
    end

    test "create_slot/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Publishing.create_slot(@invalid_attrs)
    end

    test "update_slot/2 with valid data updates the slot" do
      slot = slot_fixture()

      update_attrs = %{
        status: "some updated status",
        scheduled_at: ~U[2026-09-14 05:47:00Z],
        idempotency_key: "some updated idempotency_key"
      }

      assert {:ok, %Slot{} = slot} = Publishing.update_slot(slot, update_attrs)
      assert slot.status == "some updated status"
      assert slot.scheduled_at == ~U[2026-09-14 05:47:00Z]
      assert slot.idempotency_key == "some updated idempotency_key"
    end

    test "update_slot/2 with invalid data returns error changeset" do
      slot = slot_fixture()
      assert {:error, %Ecto.Changeset{}} = Publishing.update_slot(slot, @invalid_attrs)
      assert slot == Publishing.get_slot!(slot.id)
    end

    test "delete_slot/1 deletes the slot" do
      slot = slot_fixture()
      assert {:ok, %Slot{}} = Publishing.delete_slot(slot)
      assert_raise Ecto.NoResultsError, fn -> Publishing.get_slot!(slot.id) end
    end

    test "change_slot/1 returns a slot changeset" do
      slot = slot_fixture()
      assert %Ecto.Changeset{} = Publishing.change_slot(slot)
    end
  end
end
