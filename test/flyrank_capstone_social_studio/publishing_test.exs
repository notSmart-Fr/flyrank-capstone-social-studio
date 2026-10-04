defmodule FlyrankCapstoneSocialStudio.PublishingTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.Publishing.PublishAttempt
  alias FlyrankCapstoneSocialStudio.Publishing.Slot
  alias FlyrankCapstoneSocialStudio.Publishing.Workers.PublishWorker
  alias FlyrankCapstoneSocialStudio.Test.{CrashingPublisher, FailingPublisher}

  setup do
    {:ok, post} =
      Content.create_post(%{
        title: "Publishing Test Post",
        content: "Behaviour tests for scheduling and dispatching.",
        source_type: "markdown"
      })

    %{post: post}
  end

  defp approved_variant!(post, platform \\ "mock_x") do
    {:ok, variant} =
      Content.create_variant(%{
        post_id: post.id,
        platform: platform,
        content: "Approved #{platform} content #tech",
        status: "approved"
      })

    variant
  end

  defp scheduled_slot!(variant, key \\ nil) do
    params = %{"scheduled_at" => DateTime.to_iso8601(DateTime.utc_now())}
    params = if key, do: Map.put(params, "idempotency_key", key), else: params

    {:ok, slot} = Publishing.schedule_variant(variant, params)
    slot
  end

  defp attempts_for(slot), do: Repo.all(from pa in PublishAttempt, where: pa.slot_id == ^slot.id)

  describe "Scheduling Behavior: slots, instant mode & auto spacing" do
    @describetag :publishing
    @describetag :scheduling

    test "creates a pending slot and enqueues exactly one Oban job", %{post: post} do
      variant = approved_variant!(post)

      assert {:ok, %Slot{status: "pending"} = slot} =
               Publishing.schedule_variant(variant, %{
                 "scheduled_at" =>
                   DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
               })

      assert_enqueued(worker: PublishWorker, args: %{"slot_id" => slot.id})
      assert [_single_job] = all_enqueued(worker: PublishWorker)
    end

    test "instant mode (enqueue: false) creates the slot without queueing a job", %{post: post} do
      variant = approved_variant!(post)

      assert {:ok, %Slot{}} =
               Publishing.schedule_variant(
                 variant,
                 %{"scheduled_at" => DateTime.to_iso8601(DateTime.utc_now())},
                 enqueue: false
               )

      refute_enqueued(worker: PublishWorker)
    end

    test "scheduling a variant that already has a slot returns it instead of duplicating", %{
      post: post
    } do
      variant = approved_variant!(post)
      first = scheduled_slot!(variant)
      second = scheduled_slot!(variant)

      assert first.id == second.id
      assert [_single_slot] = Repo.all(from s in Slot, where: s.variant_id == ^variant.id)
    end

    test "auto mode places the next slot for the same platform two hours after the last", %{
      post: post
    } do
      first_variant = approved_variant!(post, "mock_x")
      second_variant = approved_variant!(post, "mock_x")

      assert {:ok, first} = Publishing.schedule_variant(first_variant, %{}, mode: :auto)
      assert {:ok, second} = Publishing.schedule_variant(second_variant, %{}, mode: :auto)

      assert DateTime.diff(second.scheduled_at, first.scheduled_at, :second) == 2 * 3600
    end

    @tag :error_handling
    test "returns a changeset error for a past scheduled_at", %{post: post} do
      variant = approved_variant!(post)

      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Publishing.schedule_variant(variant, %{"scheduled_at" => past})

      assert "must be in the future" in errors_on(changeset).scheduled_at
      refute_enqueued(worker: PublishWorker)
    end

    @tag :error_handling
    test "rejects a duplicate idempotency key with a uniqueness error", %{post: post} do
      variant = approved_variant!(post)
      _first = scheduled_slot!(variant, "duplicate-key-999")

      assert {:error, changeset} =
               Publishing.schedule_variant(variant, %{
                 "scheduled_at" => DateTime.to_iso8601(DateTime.utc_now()),
                 "idempotency_key" => "duplicate-key-999"
               })

      assert "has already been taken" in errors_on(changeset).idempotency_key
    end

    @tag :error_handling
    test "a failed slot is reset to pending and re-enqueued when rescheduled", %{post: post} do
      variant = approved_variant!(post)
      slot = scheduled_slot!(variant)

      assert {:error, _attempt} = Publishing.dispatch_slot(slot, simulate_failure: true)
      assert Publishing.get_slot!(slot.id).status == "failed"

      retried = scheduled_slot!(variant)

      assert retried.id == slot.id
      assert retried.status == "pending"
    end
  end

  describe "Dispatch Behavior: adapters, idempotency & concurrency" do
    @describetag :publishing
    @describetag :dispatch

    setup %{post: post} do
      variant = approved_variant!(post)
      %{variant: variant, slot: scheduled_slot!(variant)}
    end

    test "a successful dispatch records one success attempt and publishes slot and variant", %{
      slot: slot,
      variant: variant
    } do
      assert {:ok, %PublishAttempt{status: "success"} = attempt} = Publishing.dispatch_slot(slot)

      assert attempt.external_post_id =~ "x-tweet-"
      assert Publishing.get_slot!(slot.id).status == "published"
      assert Content.get_variant!(variant.id).status == "published"
    end

    test "re-dispatching a published slot short-circuits without a new attempt", %{slot: slot} do
      assert {:ok, %PublishAttempt{}} = Publishing.dispatch_slot(slot)

      published_slot = Publishing.get_slot!(slot.id)

      assert {:ok, %{status: :already_published}} = Publishing.dispatch_slot(published_slot)
      assert [_single_attempt] = attempts_for(slot)
    end

    test "re-dispatching a stale pending slot returns the existing attempt", %{slot: slot} do
      assert {:ok, %PublishAttempt{} = first} = Publishing.dispatch_slot(slot)

      # `slot` is the stale in-memory struct that still says "pending"
      assert {:ok, %PublishAttempt{} = second} = Publishing.dispatch_slot(slot)

      assert first.id == second.id
    end

    @tag :error_handling
    test "a failing adapter records a failure attempt and marks the slot failed", %{slot: slot} do
      assert {:error, %PublishAttempt{status: "failure"} = attempt} =
               Publishing.dispatch_slot(slot, simulate_failure: true)

      assert attempt.error_message =~ "Simulated X platform rate limit"
      assert Publishing.get_slot!(slot.id).status == "failed"
    end

    @tag :error_handling
    test "an in-flight claim rejects another dispatch before the adapter is called", %{
      slot: slot
    } do
      {:ok, _in_flight} =
        Publishing.create_publish_attempt(%{
          slot_id: slot.id,
          adapter_name: "InFlight",
          status: "pending"
        })

      assert {:error, :concurrent_request_in_flight} = Publishing.dispatch_slot(slot)
      assert [_only_the_claim] = attempts_for(slot)
    end

    @tag :error_handling
    test "an adapter that raises is recorded as a failure and the slot stays retryable", %{
      slot: slot
    } do
      FailingPublisher.swap_adapter!(:mock_x, CrashingPublisher)

      assert {:error, %PublishAttempt{status: "failure"} = attempt} =
               Publishing.dispatch_slot(slot)

      assert attempt.error_message =~ "Adapter exception: boom from adapter"
      assert Publishing.get_slot!(slot.id).status == "failed"

      # The claim is released, so a later retry with a healthy adapter publishes
      FailingPublisher.swap_adapter!(
        :mock_x,
        FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX
      )

      retry_slot = Publishing.get_slot!(slot.id)

      assert {:ok, %PublishAttempt{status: "success"}} = Publishing.dispatch_slot(retry_slot)
    end

    @tag :error_handling
    test "simultaneous dispatches publish at most once", %{slot: slot} do
      results =
        Task.await_many([
          Task.async(fn -> Publishing.dispatch_slot(slot) end),
          Task.async(fn -> Publishing.dispatch_slot(slot) end)
        ])

      assert Enum.any?(results, &match?({:ok, %PublishAttempt{status: "success"}}, &1))
      assert [%PublishAttempt{status: "success"}] = attempts_for(slot)
    end
  end

  describe "Audit History Behavior: attempts are recorded and preloaded" do
    @describetag :publishing
    @describetag :publish_history

    setup %{post: post} do
      variant = approved_variant!(post)
      %{slot: scheduled_slot!(variant)}
    end

    test "list_history/0 returns successful attempts with slot and variant preloaded", %{
      slot: slot
    } do
      assert {:ok, attempt} = Publishing.dispatch_slot(slot)

      recorded = Enum.find(Publishing.list_history(), &(&1.id == attempt.id))

      assert recorded.status == "success"
      assert recorded.slot.id == slot.id
      assert recorded.slot.variant.id == slot.variant_id
    end

    @tag :error_handling
    test "list_history/0 returns failed attempts with their error message", %{slot: slot} do
      assert {:error, _attempt} = Publishing.dispatch_slot(slot, simulate_failure: true)

      failed = Enum.find(Publishing.list_history(), &(&1.slot_id == slot.id))

      assert failed.status == "failure"
      assert failed.error_message =~ "Simulated X platform rate limit"
    end
  end
end
