defmodule FlyrankCapstoneSocialStudioWeb.PageControllerTest do
  use FlyrankCapstoneSocialStudioWeb.ConnCase

  test "GET / renders the Social Studio live dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Social Studio"
    assert html_response(conn, 200) =~ "Ingest Blog Post"
  end
end
