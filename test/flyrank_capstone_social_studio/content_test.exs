defmodule FlyrankCapstoneSocialStudio.ContentTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content

  describe "ingestion and variant constraint profiles" do
    test "ingest_and_generate/2 creates a post and valid variants for target platforms" do
      post_params = %{
        title: "Understanding Idempotency in Elixir",
        content: "Idempotency ensures that retrying an operation produces the exact same result.",
        source_type: "markdown"
      }

      assert {:ok, {post, variants}} =
               Content.ingest_and_generate(post_params, ["telegram", "mock_x"])

      assert post.id != nil
      assert length(variants) == 2

      telegram_variant = Enum.find(variants, &(&1.platform == "telegram"))
      mock_x_variant = Enum.find(variants, &(&1.platform == "mock_x"))

      assert telegram_variant.content != nil
      assert mock_x_variant.content != nil
      assert telegram_variant.status == "draft"
    end

    test "variant changeset blocks rule-breaking content with explicit error message naming the rule" do
      # Mock X profile allows max 280 characters and 2 hashtags
      oversized_content = String.duplicate("a", 290) <> " #one #two #three"

      {:error, changeset} =
        Content.create_variant(%{
          platform: "mock_x",
          content: oversized_content,
          status: "draft"
        })

      refute changeset.valid?

      # Verify error messages name the broken constraint rules explicitly
      errors = errors_on(changeset)
      assert errors.content != nil

      error_text = Enum.join(errors.content, " ")
      assert error_text =~ "exceeds maximum character limit"
      assert error_text =~ "exceeds maximum hashtag count"
    end
  end
end
