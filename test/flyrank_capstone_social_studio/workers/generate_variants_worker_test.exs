defmodule FlyrankCapstoneSocialStudio.Workers.GenerateVariantsWorkerTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Content.GenerateAiVariants.Core, as: GenerateVariantsCore
  alias FlyrankCapstoneSocialStudio.Repo

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "AI Variant Generation & Telemetry Behavior" do
    @describetag :ai_generation

    test "executes variant generation via Gemini mock, persists drafts, and logs AI cost telemetry",
         %{bypass: bypass} do
      # 1. Seed a source post
      {:ok, {post, _variants}} =
        Content.ingest_and_template(
          %{
            "title" => "Elixir Concurrency Post",
            "content" => "BEAM processes provide fault isolation and lightweight concurrency.",
            "source_type" => "markdown"
          },
          ["telegram"]
        )

      # 2. Mock Gemini API returning valid A/B variant JSON
      # Replace Bypass.expect_once with Bypass.expect/4 or Bypass.stub/4
      Bypass.stub(bypass, "POST", "/v1beta/models/gemini-2.5-flash:generateContent", fn conn ->
        # 1. Inspect prompt or return structured JSON for both generation and grounding calls
        json_response = ~s({
    "candidates": [{
      "content": {
        "parts": [{
          "text": "{\\"variant_a\\": \\"BEAM processes isolate faults natively in Elixir.\\", \\"variant_b\\": \\"Elixir uses lightweight BEAM processes for concurrency.\\", \\"is_grounded\\": true, \\"unsupported_claims\\": []}"
        }]
      }
    }],
    "usageMetadata": {
      "promptTokenCount": 120,
      "candidatesTokenCount": 80
    }
  })

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, json_response)
      end)

      # Note: Pass api_url in opts or test overrides if your Core module supports it
      url = "http://localhost:#{bypass.port}/v1beta/models/gemini-2.5-flash:generateContent"

      # 3. Execute generation core logic
      assert {:ok, %{variant_a: draft_a, variant_b: draft_b}} =
               GenerateVariantsCore.execute(post.id, "telegram",
                 api_url: url,
                 api_key: "test_key"
               )

      # 4. Assert variant structure and token splits
      assert draft_a.variant_label == "A"
      assert draft_b.variant_label == "B"
      assert draft_a.status == "draft"
      assert draft_b.status == "draft"
      assert draft_a.prompt_tokens == 60
      assert draft_b.prompt_tokens == 60

      # 5. Assert Financial Telemetry persisted on Post
      updated_post = Content.get_post!(post.id)
      assert Decimal.gt?(updated_post.total_ai_cost, Decimal.new("0.0"))
    end

    @tag :error_handling
    test "handles Gemini API failures (500 Internal Error) without corrupting post state", %{
      bypass: bypass
    } do
      {:ok, {post, _variants}} =
        Content.ingest_and_template(
          %{
            "title" => "Failing Gemini Post",
            "content" => "Testing failure path.",
            "source_type" => "markdown"
          },
          ["telegram"]
        )

      Bypass.stub(bypass, "POST", "/v1beta/models/gemini-2.5-flash:generateContent", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      url = "http://localhost:#{bypass.port}/v1beta/models/gemini-2.5-flash:generateContent"

      assert {:error, _reason} =
               GenerateVariantsCore.execute(post.id, "telegram",
                 api_url: url,
                 api_key: "test_key"
               )
    end

    @tag :grounding
    test "marks generated variants rejected when the audit finds unsupported claims", %{
      bypass: bypass
    } do
      {:ok, {post, _variants}} =
        Content.ingest_and_template(
          %{
            "title" => "Unsupported claim",
            "content" => "The product is available today.",
            "source_type" => "markdown"
          },
          ["telegram"]
        )

      counter = start_supervised!({Agent, fn -> 0 end})

      Bypass.stub(bypass, "POST", "/v1beta/models/gemini-2.5-flash:generateContent", fn conn ->
        call = Agent.get_and_update(counter, fn call -> {call, call + 1} end)

        body =
          case call do
            0 ->
              ~s({"variant_a":"99.9% uptime","variant_b":"99.9% uptime"})

            _ ->
              ~s({"is_grounded":false,"unsupported_claims":["99.9% uptime claim"]})
          end

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, gemini_response(body, call == 0))
      end)

      url = "http://localhost:#{bypass.port}/v1beta/models/gemini-2.5-flash:generateContent"

      assert {:ok, %{variant_a: draft_a, variant_b: draft_b}} =
               GenerateVariantsCore.execute(post.id, "telegram",
                 api_url: url,
                 api_key: "test_key"
               )

      assert draft_a.status == "rejected"
      assert draft_a.rejection_reason =~ "99.9% uptime claim"
      assert draft_b.status == "rejected"
      assert draft_b.rejection_reason =~ "99.9% uptime claim"
    end

    @tag :grounding
    @tag :error_handling
    test "marks generated variants needs_review when the audit API fails", %{bypass: bypass} do
      {:ok, {post, _variants}} =
        Content.ingest_and_template(
          %{
            "title" => "Audit unavailable",
            "content" => "The product is available today.",
            "source_type" => "markdown"
          },
          ["telegram"]
        )

      counter = start_supervised!({Agent, fn -> 0 end})

      Bypass.stub(bypass, "POST", "/v1beta/models/gemini-2.5-flash:generateContent", fn conn ->
        call = Agent.get_and_update(counter, fn call -> {call, call + 1} end)

        if call == 0 do
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.resp(
            200,
            gemini_response(~s({"variant_a":"A claim","variant_b":"Another claim"}), true)
          )
        else
          Plug.Conn.resp(conn, 500, "Audit unavailable")
        end
      end)

      url = "http://localhost:#{bypass.port}/v1beta/models/gemini-2.5-flash:generateContent"

      assert {:ok, %{variant_a: draft_a, variant_b: draft_b}} =
               GenerateVariantsCore.execute(post.id, "telegram",
                 api_url: url,
                 api_key: "test_key"
               )

      assert draft_a.status == "needs_review"
      assert draft_a.rejection_reason =~ "HTTP 500"
      assert draft_b.status == "needs_review"
      assert draft_b.rejection_reason =~ "HTTP 500"

      # Verify that needs_review variants persist successfully in Content.create_variant
      assert {:ok, persisted_variant} =
               Content.create_variant(%{
                 post_id: post.id,
                 platform: "telegram",
                 content: draft_a.content,
                 status: draft_a.status,
                 rejection_reason: draft_a.rejection_reason,
                 model_used: draft_a.model_used
               })

      assert persisted_variant.status == "needs_review"
    end
  end

  defp gemini_response(response_text, include_usage?) do
    response = %{
      "candidates" => [
        %{"content" => %{"parts" => [%{"text" => response_text}]}}
      ]
    }

    response =
      if include_usage? do
        Map.put(response, "usageMetadata", %{
          "promptTokenCount" => 120,
          "candidatesTokenCount" => 80
        })
      else
        response
      end

    Jason.encode!(response)
  end
end
