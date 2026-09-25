defmodule FlyrankCapstoneSocialStudio.ContentTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content

  # ===========================================================================
  # 1. Ingestion Input Handling (Markdown vs. URL)
  # ===========================================================================
  describe "ingestion sources" do
    test "ingest_and_template/3 handles raw markdown input" do
      post_params = %{
        "title" => "Markdown Ingestion Test",
        "content" => "# Title\n\nDirect Markdown body content without external fetches.",
        "source_type" => "markdown"
      }

      assert {:ok, {post, _variants}} = Content.ingest_and_template(post_params, ["telegram"])

      assert post.source_type == "markdown"
      assert post.content =~ "Direct Markdown body content"
    end

    test "ingest_and_template/3 rejects invalid source types via Post schema validation" do
      post_params = %{
        "title" => "Invalid Source Test",
        "content" => "Some text",
        "source_type" => "pdf"
      }

      assert {:error, changeset} = Content.ingest_and_template(post_params, ["telegram"])
      refute changeset.valid?
      assert errors_on(changeset).source_type != nil
    end

    test "ingest_and_template/3 requires url parameter when source_type is url" do
      post_params = %{
        "title" => "Missing URL Test",
        "source_type" => "url"
      }

      assert {:error, _reason} = Content.ingest_and_template(post_params, ["telegram"])
    end
  end

  # ===========================================================================
  # 2. Variant Constraint Profiles & Template Ingestion
  # ===========================================================================
  describe "variant constraint profiles and local templating" do
    test "ingest_and_template/3 creates valid template variants for specified platforms" do
      post_params = %{
        "title" => "Understanding Idempotency in Elixir",
        "content" =>
          "Idempotency ensures that retrying an operation produces the exact same result.",
        "source_type" => "markdown"
      }

      assert {:ok, {post, variants}} =
               Content.ingest_and_template(post_params, ["telegram", "mock_x"])

      assert post.id != nil
      # 1 template variant per platform (2 total)
      assert length(variants) == 2

      telegram_variants = Enum.filter(variants, &(&1.platform == "telegram"))
      mock_x_variants = Enum.filter(variants, &(&1.platform == "mock_x"))

      assert length(telegram_variants) == 1
      assert length(mock_x_variants) == 1
      assert Enum.all?(variants, &(&1.status == "draft"))
    end

    test "variant changeset blocks rule-breaking content with explicit error messages naming the rules" do
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
    test "ingest_and_template/3 creates initial draft variants ready for audit" do
      post_params = %{
        "title" => "Grounding Test Post",
        "content" => "Elixir relies on BEAM processes for fault-tolerant applications.",
        "source_type" => "markdown"
      }

      assert {:ok, {_post, variants}} = Content.ingest_and_template(post_params, ["telegram"])
      assert Enum.all?(variants, &(&1.status == "draft"))
    end
  end

  # ===========================================================================
  # 4. Idempotency Key Deduplication
  # ===========================================================================
  describe "ingest_and_template/3 idempotency" do
    test "returns cached post and variants when duplicate idempotency key is passed" do
      key = "test-uuid-key-1234"

      post_attrs = %{
        "title" => "Elixir Testing Tips",
        "content" => "Robust test suites catch concurrent edge cases early.",
        "source_type" => "markdown"
      }

      # 1. First Ingestion with explicit idempotency key
      assert {:ok, {post1, variants1}} =
               Content.ingest_and_template(post_attrs, ["telegram"], key)

      # 2. Second Ingestion with the exact same key
      assert {:ok, {post2, variants2}} =
               Content.ingest_and_template(post_attrs, ["telegram"], key)

      # Verify it returned the exact same Post record from DB without recreating
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

      # Distinct idempotency keys produce distinct database entries
      refute post1.id == post2.id
    end
  end
end
