defmodule FlyrankCapstoneSocialStudioWeb.PageControllerTest do
  use FlyrankCapstoneSocialStudioWeb.ConnCase

  test "GET / renders the Social Studio live dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Content Ingestion Studio"
    assert html =~ "Ingest New Content"
  end
end
