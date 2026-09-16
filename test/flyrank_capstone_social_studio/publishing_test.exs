defmodule FlyrankCapstoneSocialStudio.PublishingTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing

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
      # Execute dispatch
      assert {:ok, attempt} = Publishing.dispatch_slot(slot)

      # Fetch history
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
      # Execute dispatch with simulated failure
      assert {:error, _reason} = Publishing.dispatch_slot(slot, simulate_failure: true)

      # Fetch history
      history = Publishing.list_history()
      failed_attempt = Enum.find(history, &(&1.slot_id == slot.id))

      assert failed_attempt != nil
      assert failed_attempt.status == "failure"
      assert failed_attempt.error_message =~ "Simulated X platform rate limit"
    end
  end
end
