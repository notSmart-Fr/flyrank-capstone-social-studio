defmodule FlyrankCapstoneSocialStudio.DurableSchedulerTest do
  use FlyrankCapstoneSocialStudio.DataCase
  use Oban.Testing, repo: FlyrankCapstoneSocialStudio.Repo

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.Publishing.PublishAttempt
  alias FlyrankCapstoneSocialStudio.Publishing.Workers.PublishWorker

  describe "Phase 5 Gate: Oban Worker Execution & History Audit Log" do
    setup do
      {:ok, post} =
        Content.create_post(%{
          title: "Durable Scheduler Test",
          content: "Testing background execution using Oban.",
          source_type: "markdown"
        })

      {:ok, variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "mock_x",
          content: "Durable job execution tweet #tech",
          status: "draft"
        })

      {:ok, approved} = Content.approve_variant(variant)

      {:ok, slot} =
        Publishing.schedule_variant(approved, %{
          "scheduled_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "status" => "pending",
          "idempotency_key" => "key-oban-505"
        })

      %{post: post, variant: variant, slot: slot}
    end

    test "Oban worker enqueues job and transitions slot to published upon perform", %{slot: slot} do
      # Prove an Oban job was enqueued for the worker
      assert_enqueued(worker: PublishWorker, args: %{"slot_id" => slot.id})

      # Perform the enqueued Oban job synchronously
      assert :ok = perform_job(PublishWorker, %{"slot_id" => slot.id})

      # Verify slot transitions to published state
      updated_slot = Publishing.get_slot!(slot.id)
      assert updated_slot.status == "published"
    end

    test "publishing history records attempt details in audit log", %{slot: slot} do
      # Perform the worker job
      perform_job(PublishWorker, %{"slot_id" => slot.id})

      # Retrieve history logs
      history = Publishing.list_history()
      assert length(history) >= 1

      [latest_attempt | _] = history
      assert latest_attempt.slot_id == slot.id
      assert latest_attempt.status == "success"
      assert latest_attempt.external_post_id =~ "x-tweet-"
    end

    test "re-executing worker after restart/retry succeeds with zero duplicate posts", %{
      slot: slot
    } do
      # Initial execution (e.g. worker process started)
      assert :ok = perform_job(PublishWorker, %{"slot_id" => slot.id})

      # Simulated restart/retry execution (e.g. Oban retries after worker crash mid-batch)
      assert :ok = perform_job(PublishWorker, %{"slot_id" => slot.id})

      # Verify slot remains published
      updated_slot = Publishing.get_slot!(slot.id)
      assert updated_slot.status == "published"

      # Verify only 1 publish attempt was recorded despite worker re-execution
      attempts = Repo.all(from pa in PublishAttempt, where: pa.slot_id == ^slot.id)
      assert length(attempts) == 1
    end
  end
end
