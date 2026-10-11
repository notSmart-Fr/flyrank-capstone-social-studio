defmodule FlyrankCapstoneSocialStudioWeb.PublishingHistoryLiveTest do
  use FlyrankCapstoneSocialStudioWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing

  setup do
    {:ok, post} =
      Content.create_post(%{
        title: "Audit History Test Post",
        content: "Testing audit history LiveView UI presentation.",
        source_type: "markdown"
      })

    {:ok, variant} =
      Content.create_variant(%{
        post_id: post.id,
        platform: "telegram",
        content: "Test Telegram Post Content #tech",
        status: "approved"
      })

    {:ok, slot} =
      Publishing.schedule_variant(variant, %{
        "scheduled_at" =>
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
      })

    %{post: post, variant: variant, slot: slot}
  end

  describe "Publishing History LiveView" do
    test "renders empty state when no attempts exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/publishing/history")

      assert html =~ "Publishing Audit Trail"
      assert html =~ "No publishing attempts recorded yet"
    end

    test "renders audit attempt row with status badge and platform metadata", %{
      conn: conn,
      slot: slot
    } do
      {:ok, _attempt} =
        Publishing.create_publish_attempt(%{
          slot_id: slot.id,
          adapter_name: "FlyrankCapstoneSocialStudio.Publishing.Adapters.Telegram",
          status: "success",
          external_post_id: "tg_msg_98765",
          response_payload: %{raw_response: "Message delivered successfully"}
        })

      {:ok, _view, html} = live(conn, ~p"/publishing/history")

      assert html =~ "Publishing Audit Trail"
      assert html =~ "Telegram"
      assert html =~ "tg_msg_98765"
      assert html =~ "Audit History Test Post"
    end

    test "inspects failed attempt displaying constraint violation diagnostic payload", %{
      conn: conn,
      slot: slot
    } do
      {:ok, attempt} =
        Publishing.create_publish_attempt(%{
          slot_id: slot.id,
          adapter_name: "FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX",
          status: "failure",
          error_message: "Constraint violation at publish time: [:content_too_long]"
        })

      {:ok, view, _html} = live(conn, ~p"/publishing/history")

      # Click the inspect button for the attempt
      html =
        view
        |> element("button#inspect-attempt-#{attempt.id}")
        |> render_click()

      assert html =~ "Constraint violation at publish time: [:content_too_long]"
      assert html =~ "Diagnostic Payload"
    end

    test "updates dynamically when real-time publish event is broadcast via PubSub", %{
      conn: conn,
      slot: slot
    } do
      {:ok, view, html} = live(conn, ~p"/publishing/history")
      assert html =~ "No publishing attempts recorded yet"

      {:ok, _new_attempt} =
        Publishing.create_publish_attempt(%{
          slot_id: slot.id,
          adapter_name: "FlyrankCapstoneSocialStudio.Publishing.Adapters.Telegram",
          status: "success",
          external_post_id: "live_tg_broadcast_123",
          response_payload: %{raw_response: "Live streamed publish"}
        })

      # Broadcast over PubSub like PublishWorker does
      Phoenix.PubSub.broadcast(
        FlyrankCapstoneSocialStudio.PubSub,
        "publishing:events",
        {:slot_published, slot}
      )

      rendered = render(view)
      assert rendered =~ "live_tg_broadcast_123"
      assert rendered =~ "Telegram"
    end
  end
end
