defmodule FlyrankCapstoneSocialStudio.PublishingTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.Publishing.Slot

  describe "scheduling invariants & blocked variants" do
    setup do
      {:ok, post} =
        Content.create_post(%{
          title: "Invariants Test Post",
          content: "Testing variant scheduling guards.",
          source_type: "markdown"
        })

      {:ok, approved_variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "telegram",
          content: "Approved variant content",
          status: "approved"
        })

      {:ok, draft_variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "mock_x",
          content: "Draft variant content",
          status: "draft"
        })

      {:ok, rejected_variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "mock_linkedin",
          content: "Rejected variant content",
          status: "rejected"
        })

      %{
        approved_variant: approved_variant,
        draft_variant: draft_variant,
        rejected_variant: rejected_variant
      }
    end

    test "refuses to schedule a draft variant", %{draft_variant: variant} do
      params = %{
        "scheduled_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "idempotency_key" => "key-draft-#{:erlang.unique_integer([:positive])}"
      }

      # Update test lines 54 & 63 in publishing_test.exs:
      assert {:error, :unapproved_variant} = Publishing.schedule_variant(variant, params)
    end

    test "refuses to schedule a blocked/rejected variant", %{rejected_variant: variant} do
      params = %{
        "scheduled_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "idempotency_key" => "key-rejected-#{:erlang.unique_integer([:positive])}"
      }

      assert {:error, :unapproved_variant} = Publishing.schedule_variant(variant, params)
    end

    test "allows scheduling an approved variant", %{approved_variant: variant} do
      params = %{
        "scheduled_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "idempotency_key" => "key-approved-#{:erlang.unique_integer([:positive])}"
      }

      assert {:ok, %Slot{}} = Publishing.schedule_variant(variant, params)
    end
  end

  describe "duplicate publish & idempotency" do
    setup do
      {:ok, post} =
        Content.create_post(%{
          title: "Idempotency Test Post",
          content: "Testing duplicate publishing.",
          source_type: "markdown"
        })

      {:ok, variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "mock_x",
          content: "Idempotency test content",
          status: "approved"
        })

      {:ok, slot} =
        Publishing.schedule_variant(variant, %{
          "scheduled_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "status" => "pending",
          "idempotency_key" => "key-idempotent-#{:erlang.unique_integer([:positive])}"
        })

      %{variant: variant, slot: slot}
    end

    test "short-circuits gracefully when slot is already published", %{slot: slot} do
      # First dispatch marks it published
      assert {:ok, _attempt} = Publishing.dispatch_slot(slot)

      # Reload slot to fetch status = "published"
      published_slot = Repo.get!(Slot, slot.id)

      # Second dispatch short-circuits safely
      assert {:ok, %{status: :already_published}} = Publishing.dispatch_slot(published_slot)
    end

    test "prevents creating duplicate slots with the same idempotency key", %{variant: variant} do
      key = "duplicate-key-999"

      params = %{
        "scheduled_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "idempotency_key" => key
      }

      # First schedule succeeds
      assert {:ok, %Slot{}} = Publishing.schedule_variant(variant, params)

      # Second schedule with identical idempotency key fails DB unique constraint
      assert {:error, changeset} = Publishing.schedule_variant(variant, params)
      assert "has already been taken" in errors_on(changeset).idempotency_key
    end
  end

  describe "publish history & audit logs" do
    setup do
      {:ok, post} =
        Content.create_post(%{
          title: "Audit History Test Post",
          content: "Testing history audit log visibility.",
          source_type: "markdown"
        })

      {:ok, variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "mock_x",
          content: "Audit test content #tech",
          status: "approved"
        })

      {:ok, slot} =
        Publishing.schedule_variant(variant, %{
          "scheduled_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "status" => "pending",
          "idempotency_key" => "key-audit-#{:erlang.unique_integer([:positive])}"
        })

      %{variant: variant, slot: slot}
    end

    test "list_history/0 records and preloads successful publish attempts", %{slot: slot} do
      assert {:ok, attempt} = Publishing.dispatch_slot(slot)

      history = Publishing.list_history()
      assert length(history) >= 1

      recorded = Enum.find(history, &(&1.id == attempt.id))
      assert recorded != nil
      assert recorded.status == "success"
      assert recorded.external_post_id =~ "x-tweet-"
      assert recorded.slot.id == slot.id
      assert recorded.slot.variant.id == slot.variant_id
    end

    test "list_history/0 records failed publish attempts with error messages", %{slot: slot} do
      assert {:error, _reason} = Publishing.dispatch_slot(slot, simulate_failure: true)

      history = Publishing.list_history()
      failed_attempt = Enum.find(history, &(&1.slot_id == slot.id))

      assert failed_attempt != nil
      assert failed_attempt.status == "failure"
      assert failed_attempt.error_message =~ "Simulated X platform rate limit"
    end
  end
end
