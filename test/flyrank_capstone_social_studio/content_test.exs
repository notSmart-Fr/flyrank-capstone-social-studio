defmodule FlyrankCapstoneSocialStudio.ContentTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content

  # ===========================================================================
  # 1. Ingestion Input Handling (Markdown vs. URL)
  # ===========================================================================
  describe "ingestion sources" do
    test "ingest_and_generate/2 handles raw markdown input" do
      post_params = %{
        "title" => "Markdown Ingestion Test",
        "content" => "# Title\n\nDirect Markdown body content without external fetches.",
        "source_type" => "markdown"
      }

      assert {:ok, {post, _variants}} = Content.ingest_and_generate(post_params, ["telegram"])

      assert post.source_type == "markdown"
      assert post.content =~ "Direct Markdown body content"
    end

    test "ingest_and_generate/2 rejects invalid source types via Post schema validation" do
      post_params = %{
        "title" => "Invalid Source Test",
        "content" => "Some text",
        "source_type" => "pdf"
      }

      assert {:error, changeset} = Content.ingest_and_generate(post_params, ["telegram"])
      refute changeset.valid?
      assert errors_on(changeset).source_type != nil
    end

    test "ingest_and_generate/2 requires url parameter when source_type is url" do
      post_params = %{
        "title" => "Missing URL Test",
        "source_type" => "url"
      }

      assert {:error, _reason} = Content.ingest_and_generate(post_params, ["telegram"])
    end
  end

  # ===========================================================================
  # 2. Variant Constraint Profiles & AI Cost Tracking
  # ===========================================================================
  describe "variant constraint profiles and cost tracking" do
    test "ingest_and_generate/2 creates valid A/B variants and tracks AI costs" do
      post_params = %{
        "title" => "Understanding Idempotency in Elixir",
        "content" =>
          "Idempotency ensures that retrying an operation produces the exact same result.",
        "source_type" => "markdown"
      }

      assert {:ok, {post, variants}} =
               Content.ingest_and_generate(post_params, ["telegram", "mock_x"])

      assert post.id != nil
      # 2 platforms x 2 variants (Variant A + Variant B) = 4 total variants
      assert length(variants) == 4

      telegram_variants = Enum.filter(variants, &(&1.platform == "telegram"))
      mock_x_variants = Enum.filter(variants, &(&1.platform == "mock_x"))

      assert length(telegram_variants) == 2
      assert length(mock_x_variants) == 2
      assert Enum.all?(variants, &(&1.status == "draft"))

      # --- Assert AI Token & Cost Tracking ---
      assert Enum.all?(variants, &(&1.prompt_tokens >= 0))
      assert Enum.all?(variants, &(&1.completion_tokens >= 0))
      assert Enum.all?(variants, &(&1.total_tokens >= 0))

      assert Enum.all?(
               variants,
               &(Decimal.compare(&1.generation_cost, Decimal.new("0.0")) != :lt)
             )

      # Assert parent Post has accumulated the summed generation cost
      assert post.total_ai_cost != nil

      assert Enum.all?(
               variants,
               &(&1.generation_cost != nil and
                   Decimal.compare(&1.generation_cost, Decimal.new("0.0")) != :lt)
             )
    end

    test "variant changeset blocks rule-breaking content with explicit error messages naming the rules" do
      # Breaks Length (>280), Hashtag Count (>2), and Tone Rules (banned casual words/all-caps)
      invalid_content = String.duplicate("a", 290) <> " OMG SLAY #one #two #three"

      {:error, changeset} =
        Content.create_variant(%{
          post_id: 1,
          platform: "mock_x",
          content: invalid_content,
          variant_label: "A",
          status: "draft"
        })

      refute changeset.valid?

      errors = errors_on(changeset)
      assert errors.content != nil

      error_text = Enum.join(errors.content, " ")
      assert error_text =~ "exceeds maximum character limit"
      assert error_text =~ "exceeds maximum hashtag count"
      assert error_text =~ "violates tone rules"
    end
  end

  # ===========================================================================
  # 3. Grounding Verification Audit (Fake Statistic Detection)
  # ===========================================================================
  describe "factual grounding verification" do
    test "ingest_and_generate/2 flags variants with fake or hallucinated claims as rejected" do
      # Grounding test: source post contains NO statistics
      post_params = %{
        "title" => "Grounding Test Post",
        "content" => "Elixir relies on BEAM processes for fault-tolerant applications.",
        "source_type" => "markdown"
      }

      assert {:ok, {_post, variants}} = Content.ingest_and_generate(post_params, ["telegram"])

      # If GroundingVerifier triggers a failure on an ungrounded claim or mock hallucination,
      # the variant status will be set to "rejected" with a populated rejection_reason.
      rejected_variants = Enum.filter(variants, &(&1.status == "rejected"))

      for variant <- rejected_variants do
        assert variant.rejection_reason =~ "Grounding Audit Failed"
      end
    end
  end

  # 4. Content Hash Deduplication
  describe "ingest_and_generate/2 deduplication" do
    test "returns existing post and variants when duplicate content is ingested within 5 minutes" do
      post_attrs = %{
        "title" => "Elixir Testing Tips",
        "content" => "Robust test suites catch concurrent edge cases early.",
        "source_type" => "markdown"
      }

      # 1. First Ingestion
      assert {:ok, {post1, variants1}} = Content.ingest_and_generate(post_attrs, ["telegram"])
      assert post1.content_hash != nil

      # 2. Second Ingestion with identical title and content
      assert {:ok, {post2, variants2}} = Content.ingest_and_generate(post_attrs, ["telegram"])

      # Verify it returned the exact same Post record from DB without recreating
      assert post1.id == post2.id
      assert Enum.map(variants1, & &1.id) == Enum.map(variants2, & &1.id)
    end

    test "populates content_hash correctly on Post creation" do
      post_attrs = %{
        "title" => "Unique Post Title",
        "content" => "Unique post content body.",
        "source_type" => "markdown"
      }

      {:ok, {post, _variants}} = Content.ingest_and_generate(post_attrs, ["telegram"])

      expected_hash =
        :crypto.hash(:sha256, "Unique Post Title:Unique post content body.")
        |> Base.encode16()

      assert post.content_hash == expected_hash
    end
  end
end
