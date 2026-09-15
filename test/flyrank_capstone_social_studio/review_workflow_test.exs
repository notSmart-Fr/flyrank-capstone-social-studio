defmodule FlyrankCapstoneSocialStudio.ReviewWorkflowTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing

  describe "Phase 3 Gate: Review Workflow & Scheduling Protection" do
    setup do
      {:ok, post} =
        Content.create_post(%{
          title: "Review Test Post",
          content: "Content for review workflow testing.",
          source_type: "markdown"
        })

      {:ok, variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "telegram",
          content: "Telegram variant content #tech",
          status: "draft"
        })

      %{post: post, variant: variant}
    end

    test "refuses to schedule a variant in draft status", %{variant: variant} do
      slot_params = %{
        "scheduled_at" =>
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601(),
        "status" => "pending",
        "idempotency_key" => "key-draft-1"
      }

      assert {:error, :unapproved_variant} = Publishing.schedule_variant(variant, slot_params)
    end

    test "refuses to schedule a rejected variant", %{variant: variant} do
      {:ok, rejected_variant} = Content.reject_variant(variant, "Tone inaccurate")

      slot_params = %{
        "scheduled_at" =>
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601(),
        "status" => "pending",
        "idempotency_key" => "key-rejected-1"
      }

      assert {:error, :unapproved_variant} =
               Publishing.schedule_variant(rejected_variant, slot_params)
    end

    test "successfully schedules an approved variant", %{variant: variant} do
      {:ok, approved_variant} = Content.approve_variant(variant)
      assert approved_variant.status == "approved"

      slot_params = %{
        "scheduled_at" =>
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601(),
        "status" => "pending",
        "idempotency_key" => "key-approved-1"
      }

      assert {:ok, slot} = Publishing.schedule_variant(approved_variant, slot_params)
      assert slot.variant_id == variant.id
      assert slot.idempotency_key == "key-approved-1"
    end
  end
end
