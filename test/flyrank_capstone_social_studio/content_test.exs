defmodule FlyrankCapstoneSocialStudio.ContentTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Content.GroundingVerifier
  alias FlyrankCapstoneSocialStudio.Repo

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "Ingestion Behavior: Local Markdown & Scraped URL" do
    @describetag :content_ingestion

    # -------------------------------------------------------------------------
    # 1. Direct Markdown Ingestion
    # -------------------------------------------------------------------------
    test "ingests raw markdown directly and initializes platform variants in draft" do
      params = %{
        "title" => "Campaign Launch",
        "content" => "# New Features\n\nDirect Markdown text body.",
        "source_type" => "markdown"
      }

      assert {:ok, {post, variants}} = Content.ingest_and_template(params, ["telegram", "mock_x"])

      assert post.source_type == "markdown"
      assert length(variants) == 2
      assert Enum.all?(variants, &(&1.status == "draft"))
    end

    # -------------------------------------------------------------------------
    # 2. Successful Web Scraping via URL
    # -------------------------------------------------------------------------
    test "scrapes HTML body from target URL, parses content via Floki, and creates variants" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/blog/post-1", fn conn ->
        html_response = """
        <!DOCTYPE html>
        <html>
          <body>
            <article>
              <h1>Parsed Blog Title</h1>
              <p>This is scraped content extracted from the HTML DOM.</p>
            </article>
          </body>
        </html>
        """

        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html; charset=utf-8")
        |> Plug.Conn.resp(200, html_response)
      end)

      url = "http://localhost:#{bypass.port}/blog/post-1"
      params = %{"title" => "URL Ingest", "source_type" => "url", "url" => url}

      assert {:ok, {post, _variants}} = Content.ingest_and_template(params, ["telegram"])
      assert post.content =~ "scraped content extracted from the HTML DOM"
    end

    # -------------------------------------------------------------------------
    # 3. Scraping Failure Handling (500 Error & Network Drop)
    # -------------------------------------------------------------------------
    @tag :error_handling
    test "handles remote server 500 errors during scraping gracefully without creating corrupted DB records" do
      bypass = Bypass.open()

      # Use stub instead of expect_once so Req can retry safely
      Bypass.stub(bypass, "GET", "/blog/broken", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      url = "http://localhost:#{bypass.port}/blog/broken"
      params = %{"title" => "Failed Ingest", "source_type" => "url", "url" => url}

      assert {:error, "HTTP request failed with status 500"} =
               Content.ingest_and_template(params, ["telegram"])

      assert Repo.aggregate(FlyrankCapstoneSocialStudio.Content.Post, :count) == 0
    end

    @tag :error_handling
    test "handles network timeout during scraping safely" do
      bypass = Bypass.open()
      # Simulates unreachable server/dropped socket
      Bypass.down(bypass)

      url = "http://localhost:#{bypass.port}/blog/unreachable"
      params = %{"title" => "Timeout Ingest", "source_type" => "url", "url" => url}

      assert {:error, "Failed to reach URL: " <> _reason} =
               Content.ingest_and_template(params, ["telegram"])
    end
  end

  describe "Constraint Verification Behavior" do
    @describetag :content_ingestion
    @describetag :constraint_profiles

    # -------------------------------------------------------------------------
    # 4. Constraint Profile Failures
    # -------------------------------------------------------------------------
    test "flags variants that violate platform character or hashtag rules with explicit error keys" do
      # Content that violates X/Twitter 280-char limit and hashtag limits
      overly_long_content =
        String.duplicate("Elixir is fast. ", 25) <> " #one #two #three #four #five"

      assert {:error, changeset} =
               Content.create_variant(%{
                 post_id: 1,
                 platform: "mock_x",
                 content: overly_long_content,
                 variant_label: "A",
                 status: "draft"
               })

      refute changeset.valid?
      errors = errors_on(changeset)

      assert errors.content != nil
      error_msg = Enum.join(errors.content, " ")
      assert error_msg =~ "exceeds maximum character limit"
    end
  end

  # -------------------------------------------------------------------------
  # 5. Grounding Verifier Behavioral Audit
  # -------------------------------------------------------------------------
  describe "GroundingVerifier behavior" do
    @describetag :grounding

    test "returns {:ok, :grounded} when Gemini confirms factual match", %{bypass: bypass} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/v1beta/models/gemini-2.5-flash:generateContent",
        fn conn ->
          json_payload = ~s({
          "candidates": [{
            "content": {
              "parts": [{"text": "{\\"is_grounded\\": true, \\"unsupported_claims\\": []}"}]
            }
          }]
        })

          Plug.Conn.resp(conn, 200, json_payload)
        end
      )

      url = "http://localhost:#{bypass.port}/v1beta/models/gemini-2.5-flash:generateContent"
      source = "Elixir uses BEAM processes."
      variant = "BEAM processes are used by Elixir."

      assert {:ok, :grounded} =
               GroundingVerifier.verify_grounding(source, variant,
                 api_url: url,
                 api_key: "test_key"
               )
    end

    @tag :error_handling
    test "returns {:error, :hallucination_detected, _} when unsupported claims exist", %{
      bypass: bypass
    } do
      Bypass.expect_once(
        bypass,
        "POST",
        "/v1beta/models/gemini-2.5-flash:generateContent",
        fn conn ->
          json_payload = ~s({
          "candidates": [{
            "content": {
              "parts": [{"text": "{\\"is_grounded\\": false, \\"unsupported_claims\\": [\\"99.9% uptime claim\\"]}"}]
            }
          }]
        })

          Plug.Conn.resp(conn, 200, json_payload)
        end
      )

      url = "http://localhost:#{bypass.port}/v1beta/models/gemini-2.5-flash:generateContent"

      assert {:error, :hallucination_detected, ["99.9% uptime claim"]} =
               GroundingVerifier.verify_grounding("Source", "Variant with 99.9% uptime",
                 api_url: url,
                 api_key: "test_key"
               )
    end

    @tag :error_handling
    test "returns {:error, :audit_failed, _} when remote API returns HTTP 500", %{bypass: bypass} do
      Bypass.stub(bypass, "POST", "/v1beta/models/gemini-2.5-flash:generateContent", fn conn ->
        Plug.Conn.resp(conn, 500, "Server Error")
      end)

      url = "http://localhost:#{bypass.port}/v1beta/models/gemini-2.5-flash:generateContent"

      assert {:error, :audit_failed, "Gemini API returned HTTP 500"} =
               GroundingVerifier.verify_grounding("Source", "Variant",
                 api_url: url,
                 api_key: "test_key"
               )
    end
  end

  # ===========================================================================
  # Idempotency & Concurrency Locks Behavior
  # ===========================================================================
  describe "ingest_and_template/3 idempotency behavior" do
    @describetag :idempotency

    test "returns cached post and variants when duplicate idempotency key is passed" do
      key = "test-uuid-key-1234"

      post_attrs = %{
        "title" => "Elixir Testing Tips",
        "content" => "Robust test suites catch concurrent edge cases early.",
        "source_type" => "markdown"
      }

      assert {:ok, {post1, variants1}} =
               Content.ingest_and_template(post_attrs, ["telegram"], key)

      assert {:ok, {post2, variants2}} =
               Content.ingest_and_template(post_attrs, ["telegram"], key)

      # Verify exact record reuse from DB
      assert post1.id == post2.id
      assert Enum.map(variants1, & &1.id) == Enum.map(variants2, & &1.id)
    end

    test "allows identical content ingestion when distinct idempotency keys are used" do
      key1 = Ecto.UUID.generate()
      key2 = Ecto.UUID.generate()

      post_attrs = %{
        "title" => "Identical Title",
        "content" => "Identical body content.",
        "source_type" => "markdown"
      }

      {:ok, {post1, _variants1}} = Content.ingest_and_template(post_attrs, ["telegram"], key1)
      {:ok, {post2, _variants2}} = Content.ingest_and_template(post_attrs, ["telegram"], key2)

      refute post1.id == post2.id
    end

    @tag :error_handling
    test "returns {:error, :concurrent_request_in_flight} when key is currently processing" do
      key = Ecto.UUID.generate()

      # Seed an in-flight key in "processing" state directly in DB
      Repo.insert!(%FlyrankCapstoneSocialStudio.Content.IdempotencyKey{
        key: key,
        status: "processing"
      })

      post_attrs = %{
        "title" => "In Flight Test",
        "content" => "Testing concurrent lock behavior.",
        "source_type" => "markdown"
      }

      # Assert immediate rejection without reprocessing
      assert {:error, :concurrent_request_in_flight} =
               Content.ingest_and_template(post_attrs, ["telegram"], key)
    end

    @tag :error_handling
    test "handles concurrent race conditions safely via database unique constraint" do
      key = "race-condition-key-" <> Ecto.UUID.generate()

      post_attrs = %{
        "title" => "Concurrent Race Test",
        "content" => "Simulating simultaneous requests.",
        "source_type" => "markdown"
      }

      # Spawn 2 parallel BEAM processes trying to ingest with the exact same key at the same millisecond
      task1 = Task.async(fn -> Content.ingest_and_template(post_attrs, ["telegram"], key) end)
      task2 = Task.async(fn -> Content.ingest_and_template(post_attrs, ["telegram"], key) end)

      results = [Task.await(task1), Task.await(task2)]

      # Assert strict idempotency: Exactly 1 process succeeds, 1 receives the lock error
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :concurrent_request_in_flight}, &1)) == 1
    end
  end
end
