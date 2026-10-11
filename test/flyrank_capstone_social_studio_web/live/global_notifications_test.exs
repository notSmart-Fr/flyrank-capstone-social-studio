defmodule FlyrankCapstoneSocialStudioWeb.GlobalNotificationsTest do
  use FlyrankCapstoneSocialStudioWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias FlyrankCapstoneSocialStudio.Content
  alias Phoenix.PubSub

  describe "Global Notifications & Floating Toaster" do
    test "displays floating toast on /analytics when grounding verification completes", %{
      conn: conn
    } do
      {:ok, post} =
        Content.create_post(%{
          title: "Global Toast Post",
          content: "Original post content for factual claims.",
          source_type: "markdown"
        })

      {:ok, variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "telegram",
          content: "Verified claims content",
          status: "draft"
        })

      {:ok, view, _html} = live(conn, ~p"/analytics")

      # Simulate background grounding worker completion broadcast
      PubSub.broadcast(
        FlyrankCapstoneSocialStudio.PubSub,
        "grounding:events",
        {:grounding_verified, variant}
      )

      # Ensure the LiveView receives and renders the floating toast
      assert render(view) =~ "Grounding verified for Post ##{post.id}"
      assert has_element?(view, "#flash-toaster-group")
      assert has_element?(view, "#flash-toast-info")
      assert has_element?(view, "button[aria-label='Close notification']")
    end

    test "displays floating toast on /posts when publish worker succeeds", %{conn: conn} do
      {:ok, post} =
        Content.create_post(%{
          title: "Publish Toast Post",
          content: "Post content for publishing.",
          source_type: "markdown"
        })

      {:ok, variant} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "telegram",
          content: "Ready variant",
          status: "approved"
        })

      slot = %FlyrankCapstoneSocialStudio.Publishing.Slot{
        id: 9999,
        status: "published",
        variant_id: variant.id,
        variant: variant
      }

      {:ok, view, _html} = live(conn, ~p"/posts")

      PubSub.broadcast(
        FlyrankCapstoneSocialStudio.PubSub,
        "publishing:events",
        {:slot_published, slot}
      )

      assert render(view) =~ "Post slot #9999 (Telegram) published successfully!"
      assert has_element?(view, "#flash-toaster-group")
      assert has_element?(view, "#flash-toast-info")
    end

    test "allows user to dismiss toast via clear-flash button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analytics")

      PubSub.broadcast(
        FlyrankCapstoneSocialStudio.PubSub,
        "publishing:events",
        {:slot_failed, %FlyrankCapstoneSocialStudio.Publishing.Slot{id: 8888}, "Network timeout"}
      )

      assert render(view) =~ "Publishing failed: Network timeout"
      assert has_element?(view, "#flash-toast-error")

      # Click the dismiss button
      view
      |> element("button[aria-label='Close notification']")
      |> render_click()

      refute render(view) =~ "Publishing failed: Network timeout"
    end
  end
end

