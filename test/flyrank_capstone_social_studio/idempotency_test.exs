defmodule FlyrankCapstoneSocialStudio.IdempotencyTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.Publishing.PublishAttempt
  alias FlyrankCapstoneSocialStudio.Publishing.Slot

  describe "Phase 4 Gate: Social Adapters & Idempotent Dispatcher" do
    setup do
      {:ok, post} =
        Content.create_post(%{
          title: "Idempotency Test",
          content: "Testing idempotency guarantees.",
          source_type: "markdown"
        })

      {:ok, variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "mock_x",
          content: "Idempotency test tweet #tech",
          status: "draft"
        })

      {:ok, approved} = Content.approve_variant(variant)

      {:ok, slot} =
        Publishing.schedule_variant(approved, %{
          "scheduled_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "status" => "pending",
          "idempotency_key" => "key-idempotency-101"
        })

      %{slot: slot}
    end

    test "dispatches successfully on first run and creates a single publish attempt", %{
      slot: slot
    } do
      assert {:ok, attempt} = Publishing.dispatch_slot(slot)
      assert attempt.status == "success"
      assert attempt.external_post_id =~ "x-tweet-"

      # Verify slot status updated to published
      updated_slot = Publishing.get_slot!(slot.id)
      assert updated_slot.status == "published"
    end

    test "re-dispatching an already published slot returns existing attempt without duplicates (idempotency)",
         %{slot: slot} do
      # First run
      assert {:ok, attempt1} = Publishing.dispatch_slot(slot)

      # Second run (simulating retry / duplicate worker call)
      assert {:ok, attempt2} = Publishing.dispatch_slot(slot)

      # Proves both calls returned the identical attempt record ID
      assert attempt1.id == attempt2.id
      assert attempt1.external_post_id == attempt2.external_post_id

      # Database check: strictly ONE attempt record exists for this slot
      attempts = Repo.all(from pa in PublishAttempt, where: pa.slot_id == ^slot.id)
      assert length(attempts) == 1
    end

    test "concurrent dispatches on the same slot result in only one publish", %{slot: slot} do
      task1 = Task.async(fn -> Publishing.dispatch_slot(slot) end)
      task2 = Task.async(fn -> Publishing.dispatch_slot(slot) end)

      results = [Task.await(task1), Task.await(task2)]

      # Assert one process executed successfully and the other short-circuited
      assert Enum.count(results, &match?({:ok, %Publishing.PublishAttempt{}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :concurrent_request_in_flight}, &1)) == 1
    end

    test "allows scheduling an approved variant and enqueues job", %{approved_variant: variant} do
      params = %{
        "scheduled_at" =>
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601(),
        "idempotency_key" => "key-approved-#{:erlang.unique_integer([:positive])}"
      }

      assert {:ok, %Slot{} = slot} = Publishing.schedule_variant(variant, params)

      # Assert Oban job was scheduled for this slot
      assert_enqueued(
        worker: FlyrankCapstoneSocialStudio.Workers.PublishVariantWorker,
        args: %{"slot_id" => slot.id}
      )
    end

    test "short-circuits gracefully when slot is already published", %{slot: slot} do
      assert {:ok, _attempt} = Publishing.dispatch_slot(slot)

      # Fetch un-preloaded slot from DB
      published_slot = Repo.get!(Slot, slot.id)

      # Asserts that dispatch_slot handles unloaded associations safely
      assert {:ok, %{status: :already_published}} = Publishing.dispatch_slot(published_slot)
    end
  end
end
