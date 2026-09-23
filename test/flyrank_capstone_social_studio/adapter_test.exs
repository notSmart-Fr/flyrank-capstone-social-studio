defmodule FlyrankCapstoneSocialStudio.AdapterTest do
  use FlyrankCapstoneSocialStudio.DataCase, async: false

  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.Content.AiGenerator

  describe "Phase 4 Gate: SocialPublisher Interface & Adapter Seam" do
    test "adapter_for_platform/1 resolves correct modules from application config" do
      assert Publishing.adapter_for_platform("telegram") ==
               FlyrankCapstoneSocialStudio.Publishing.Adapters.Telegram

      assert Publishing.adapter_for_platform("mock_x") ==
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX

      assert Publishing.adapter_for_platform("mock_linkedin") ==
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockLinkedIn
    end

    test "dynamic configuration swap changes dispatch target without modifying business logic" do
      original_config = Application.get_env(:flyrank_capstone_social_studio, :adapters)

      # Swap telegram to use MockX dynamically
      swapped_config =
        Keyword.put(
          original_config,
          :telegram,
          FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX
        )

      Application.put_env(:flyrank_capstone_social_studio, :adapters, swapped_config)

      assert Publishing.adapter_for_platform("telegram") ==
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX

      # Restore original config
      Application.put_env(:flyrank_capstone_social_studio, :adapters, original_config)
    end
  end

  # ===========================================================================
  # AI Provider Adapter Seam Tests
  # ===========================================================================
  describe "AI Provider Adapter Seam" do
    test "AiGenerator resolves configured default AI adapter" do
      configured_adapter = Application.get_env(:flyrank_capstone_social_studio, :ai_adapter)

      # Verifies default active adapter is set to GeminiAdapter
      assert configured_adapter == FlyrankCapstoneSocialStudio.Ai.Adapters.GeminiAdapter
    end

    test "dynamic AI adapter swap changes generation target without modifying business logic" do
      original_ai_adapter = Application.get_env(:flyrank_capstone_social_studio, :ai_adapter)

      # Define a lightweight Mock AI Adapter for swapping test
      defmodule TestMockAiAdapter do
        @behaviour FlyrankCapstoneSocialStudio.Ai.Provider

        @impl true
        def generate_ab_variants(_content, _platform, _profile) do
          {:ok,
           %{
             variant_a: "Swapped Mock Variant A",
             variant_b: "Swapped Mock Variant B",
             prompt_tokens: 10,
             completion_tokens: 10,
             total_tokens: 20,
             cost: Decimal.new("0.0"),
             model: "swapped-mock-ai"
           }}
        end
      end

      try do
        # Dynamically swap AI adapter in Application config
        Application.put_env(:flyrank_capstone_social_studio, :ai_adapter, TestMockAiAdapter)

        # Call AiGenerator and assert it routed through the swapped mock adapter
        assert {:ok, result} =
                 AiGenerator.generate_ab_variants("Sample text", "telegram", %{
                   max_length: 280,
                   max_hashtags: 2,
                   tone: "professional"
                 })

        assert result.variant_a == "Swapped Mock Variant A"
        assert result.model == "swapped-mock-ai"
      after
        # Always restore original application config after test execution
        Application.put_env(:flyrank_capstone_social_studio, :ai_adapter, original_ai_adapter)
      end
    end
  end
end
