defmodule FlyrankCapstoneSocialStudio.Content.AiGenerator do
  @moduledoc """
  Delegates variant generation to the configured AI provider adapter.
  """

  def generate_ab_variants(content, platform_name, profile) do
    adapter =
      Application.get_env(
        :flyrank_capstone_social_studio,
        :ai_adapter,
        FlyrankCapstoneSocialStudio.Ai.Adapters.GeminiAdapter
      )

    adapter.generate_ab_variants(content, platform_name, profile)
  end
end
