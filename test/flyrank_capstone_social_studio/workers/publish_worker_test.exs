defmodule FlyrankCapstoneSocialStudio.Publishing.Workers.PublishWorkerTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.Publishing.PublishAttempt
  alias FlyrankCapstoneSocialStudio.Publishing.Workers.PublishWorker
  alias FlyrankCapstoneSocialStudio.Test.FailingPublisher

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
        status: "approved"
      })

    {:ok, slot} =
      Publishing.schedule_variant(variant, %{
        "scheduled_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "idempotency_key" => "key-oban-#{System.unique_integer([:positive])}"
      })

    Phoenix.PubSub.subscribe(FlyrankCapstoneSocialStudio.PubSub, "post:#{post.id}")

    %{post: post, slot: slot}
  end

  describe "Worker Behavior: durable execution & restart safety" do
    @describetag :publishing
    @describetag :publish_worker

    test "performing the job publishes the slot and broadcasts to the post channel", %{
      slot: slot
    } do
      assert_enqueued(worker: PublishWorker, args: %{"slot_id" => slot.id})
      assert :ok = perform_job(PublishWorker, %{"slot_id" => slot.id})

      assert Publishing.get_slot!(slot.id).status == "published"
      assert_receive {:slot_published, %{id: slot_id}}
      assert slot_id == slot.id
    end

    test "re-running the job after a restart creates no duplicate attempt", %{slot: slot} do
      assert :ok = perform_job(PublishWorker, %{"slot_id" => slot.id})
      assert :ok = perform_job(PublishWorker, %{"slot_id" => slot.id})

      assert Publishing.get_slot!(slot.id).status == "published"

      assert [_single_attempt] =
               Repo.all(from pa in PublishAttempt, where: pa.slot_id == ^slot.id)
    end
  end

  describe "Worker Failure Behavior: errors are surfaced for Oban retry" do
    @describetag :publishing
    @describetag :publish_worker
    @describetag :error_handling

    setup do
      FailingPublisher.swap_adapter!(:mock_x, FailingPublisher)
    end

    test "returns the adapter error, marks the slot failed and broadcasts the failure", %{
      slot: slot
    } do
      assert {:error, "Simulated adapter outage"} =
               perform_job(PublishWorker, %{"slot_id" => slot.id})

      assert Publishing.get_slot!(slot.id).status == "failed"
      assert_receive {:slot_failed, %{id: slot_id}, "Simulated adapter outage"}
      assert slot_id == slot.id
    end

    test "records a failure attempt in the audit history", %{slot: slot} do
      assert {:error, _reason} = perform_job(PublishWorker, %{"slot_id" => slot.id})

      assert [%PublishAttempt{status: "failure", error_message: "Simulated adapter outage"}] =
               Repo.all(from pa in PublishAttempt, where: pa.slot_id == ^slot.id)
    end
  end
end
