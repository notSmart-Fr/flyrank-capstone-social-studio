defmodule FlyrankCapstoneSocialStudio.Content.Workers.VerifyGroundingWorkerTest do
  use FlyrankCapstoneSocialStudio.DataCase, async: true

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Content.Workers.VerifyGroundingWorker
  alias Phoenix.PubSub

  setup do
    {:ok, post} =
      Content.create_post(%{
        title: "Test Post for Async Grounding",
        content: "Product launch happening on Monday with 50% discount.",
        source_type: "markdown"
      })

    {:ok, variant} =
      Content.create_variant(%{
        post_id: post.id,
        platform: "telegram",
        content: "Launch on Monday with 50% discount! #launch",
        status: "needs_review"
      })

    %{post: post, variant: variant}
  end

  describe "VerifyGroundingWorker" do
    test "executes grounding verification, updates variant to draft, and broadcasts to PubSub", %{
      post: post,
      variant: variant
    } do
      PubSub.subscribe(FlyrankCapstoneSocialStudio.PubSub, "post:#{post.id}")

      assert :ok = perform_job(VerifyGroundingWorker, %{"variant_id" => variant.id})

      assert_receive {:grounding_verified, updated_variant}
      assert updated_variant.id == variant.id
      assert updated_variant.status == "draft"
      assert is_nil(updated_variant.rejection_reason)

      reloaded = Content.get_variant!(variant.id)
      assert reloaded.status == "draft"
    end

    test "marks variant as rejected when unsupported numbers are introduced (heuristic audit)", %{
      post: post
    } do
      {:ok, hallucinated_variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "telegram",
          content: "Launch with 99.9% uptime and 100% discount! #fake",
          status: "needs_review"
        })

      PubSub.subscribe(FlyrankCapstoneSocialStudio.PubSub, "post:#{post.id}")

      assert :ok = perform_job(VerifyGroundingWorker, %{"variant_id" => hallucinated_variant.id})

      assert_receive {:grounding_verified, updated_variant}
      assert updated_variant.status == "rejected"
      assert updated_variant.rejection_reason =~ "Grounding Audit Failed"

      reloaded = Content.get_variant!(hallucinated_variant.id)
      assert reloaded.status == "rejected"
    end

    test "is unique and idempotent: deduplicates concurrent Oban jobs for the same variant_id", %{
      variant: variant
    } do
      assert {:ok, _job1} =
               %{variant_id: variant.id}
               |> VerifyGroundingWorker.new()
               |> Oban.insert()

      # Second insert within the unique period is deduplicated
      assert {:ok, _job2} =
               %{variant_id: variant.id}
               |> VerifyGroundingWorker.new()
               |> Oban.insert()

      # Only one job exists in the queue
      assert all_enqueued(worker: VerifyGroundingWorker) |> length() == 1
    end
  end
end
