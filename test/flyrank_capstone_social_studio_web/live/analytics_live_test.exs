defmodule FlyrankCapstoneSocialStudioWeb.AnalyticsLiveTest do
  use FlyrankCapstoneSocialStudioWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias FlyrankCapstoneSocialStudio.Content

  describe "Analytics LiveView" do
    test "renders analytics dashboard with post content hashes and costs", %{conn: conn} do
      {:ok, post} =
        Content.create_post(%{
          title: "Analytics Test Post",
          content: "Testing analytics content hash and telemetry.",
          source_type: "markdown"
        })

      {:ok, _view, html} = live(conn, ~p"/analytics")

      assert html =~ "System Analytics"
      assert html =~ "Analytics Test Post"
      assert html =~ String.slice(post.content_hash, 0, 10)
      assert html =~ "N/A"
    end

    test "calculates real grounding rate for AI variants", %{conn: conn} do
      {:ok, post} =
        Content.create_post(%{
          title: "Grounding Rate Test Post",
          content: "Testing grounding rate calculation.",
          source_type: "markdown"
        })

      {:ok, _var1} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "mock_x",
          content: "Post 1 grounded content",
          status: "draft",
          model_used: "gemini-2.5-flash"
        })

      {:ok, _var2} =
        Content.create_variant(%{
          post_id: post.id,
          platform: "mock_x",
          content: "Post 2 hallucinated content",
          status: "rejected",
          rejection_reason: "Grounding Audit Failed: Hallucination detected",
          model_used: "gemini-2.5-flash"
        })

      {:ok, _view, html} = live(conn, ~p"/analytics")

      # 1 grounded out of 2 = 50.0%
      assert html =~ "50.0%"
    end
  end
end
