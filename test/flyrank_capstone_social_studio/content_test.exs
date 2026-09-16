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
  # 2. Variant Constraint Profiles Verification
  # ===========================================================================
  describe "variant constraint profiles" do
    test "ingest_and_generate/2 creates valid A/B variants for target platforms" do
      post_params = %{
        "title" => "Understanding Idempotency in Elixir",
        "content" => "Idempotency ensures that retrying an operation produces the exact same result.",
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
end
