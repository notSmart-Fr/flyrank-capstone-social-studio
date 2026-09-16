defmodule FlyrankCapstoneSocialStudio.AdapterTest do
  use FlyrankCapstoneSocialStudio.DataCase, async: false

  alias FlyrankCapstoneSocialStudio.Publishing

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
      swapped_config = Keyword.put(original_config, :telegram, FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX)
      Application.put_env(:flyrank_capstone_social_studio, :adapters, swapped_config)

      assert Publishing.adapter_for_platform("telegram") ==
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX

      # Restore original config
      Application.put_env(:flyrank_capstone_social_studio, :adapters, original_config)
    end
  end
end
