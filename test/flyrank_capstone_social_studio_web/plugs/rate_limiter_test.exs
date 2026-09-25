defmodule FlyrankCapstoneSocialStudioWeb.Plugs.RateLimiterTest do
  use FlyrankCapstoneSocialStudioWeb.ConnCase, async: false

  setup do
    if :ets.whereis(:hammer_ets_buckets) != :undefined do
      :ets.delete_all_objects(:hammer_ets_buckets)
    end

    :ok
  end

  test "allows requests under limit and halts with 429 when limit is exceeded", %{conn: conn} do
    # First requests within limit should pass (not 404/429)
    for _i <- 1..10 do
      conn =
        conn
        |> post("/api/blog-posts", %{
          "title" => "Test",
          "content" => "Hello",
          "source_type" => "markdown"
        })

      refute conn.status == 429
    end

    # Request exceeding limit should halt with 429
    failed_conn =
      conn
      |> post("/api/blog-posts", %{
        "title" => "Test",
        "content" => "Hello",
        "source_type" => "markdown"
      })

    assert failed_conn.status == 429
  end
end
