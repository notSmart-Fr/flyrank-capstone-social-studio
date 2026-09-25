defmodule FlyrankCapstoneSocialStudioWeb.Plugs.IdempotencyTest do
  use FlyrankCapstoneSocialStudioWeb.ConnCase, async: true

  alias FlyrankCapstoneSocialStudio.Content.IdempotencyKey
  alias FlyrankCapstoneSocialStudio.Repo

  describe "Idempotency via HTTP headers" do
    test "sequential retry returns cached response without duplicate execution", %{conn: conn} do
      # Generate a unique key per test run to prevent stale database lock collisions
      idempotency_key = Ecto.UUID.generate()

      payload = %{
        "title" => "Idempotent Post",
        "content" => "Testing sequential retries",
        "source_type" => "markdown"
      }

      # First Attempt: Should execute and return 201 Created
      conn1 =
        conn
        |> put_req_header("idempotency-key", idempotency_key)
        |> post("/api/blog-posts", payload)

      assert conn1.status in [200, 201]
      response1 = json_response(conn1, conn1.status)

      # Second Attempt (Same Key): Should return cached response instantly
      conn2 =
        conn
        |> put_req_header("idempotency-key", idempotency_key)
        |> post("/api/blog-posts", payload)

      assert conn2.status in [200, 201]
      response2 = json_response(conn2, conn2.status)

      # Assert payloads match and idempotency record is completed
      assert response1 == response2
      assert Repo.get_by!(IdempotencyKey, key: idempotency_key).status == "completed"
    end

    test "concurrent in-flight microsecond double-clicks handle lock conflict", %{conn: conn} do
      key = "concurrent-key-999"

      payload = %{
        "title" => "Concurrent Post",
        "content" => "Testing async hammer",
        "source_type" => "markdown"
      }

      parent = self()

      tasks =
        for _i <- 1..2 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())

            conn
            |> put_req_header("idempotency-key", key)
            |> post("/api/blog-posts", payload)
          end)
        end

      results = Enum.map(tasks, &Task.await/1)
      statuses = Enum.map(results, & &1.status)

      assert 409 in statuses or Enum.count(statuses, &(&1 in [200, 201])) == 1
    end
  end
end
