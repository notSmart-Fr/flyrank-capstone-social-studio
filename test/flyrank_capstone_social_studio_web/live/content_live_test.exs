defmodule FlyrankCapstoneSocialStudioWeb.ContentLiveTest do
  use FlyrankCapstoneSocialStudioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FlyrankCapstoneSocialStudio.Content.Post
  alias FlyrankCapstoneSocialStudio.Repo

  describe "Content ingestion UI behavior" do
    @describetag :content_ingestion
    @describetag :content_ingestion_ui

    test "submitting Markdown ingests the post and navigates to its editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      params = %{
        "post" => %{
          "title" => "UI ingestion behavior",
          "content" => "A source paragraph submitted through the ingestion form.",
          "source_type" => "markdown"
        },
        "platforms" => ["mock_x"]
      }

      render_submit(form(view, "#ingest-form", params))

      post = Repo.get_by!(Post, title: "UI ingestion behavior")
      assert_redirect(view, "/posts/#{post.id}")
      assert post.content =~ "source paragraph submitted through the ingestion form"
    end

    @tag :error_handling
    test "invalid input keeps the user on the form and reports validation failure", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/")

      params = %{
        "post" => %{
          "title" => "",
          "content" => "",
          "source_type" => "markdown"
        },
        "platforms" => ["mock_x"]
      }

      html = render_submit(form(view, "#ingest-form", params))

      assert html =~ "Validation failed"
      assert has_element?(view, "#ingest-form")
      assert Repo.aggregate(Post, :count) == 0
    end
  end
end
