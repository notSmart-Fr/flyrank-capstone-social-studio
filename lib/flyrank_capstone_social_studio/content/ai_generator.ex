defmodule FlyrankCapstoneSocialStudio.Content.AiGenerator do
  @moduledoc """
  Delegates AI variant generation to the configured AI adapter.
  """

  @doc """
  Generates A/B content variants for a given post content, platform, and constraint profile.

  Accepts optional `opts` (e.g. `:api_url`, `:api_key`) to pass down to the adapter.
  """
  def generate_ab_variants(content, platform_name, profile, opts \\ []) do
    adapter =
      Application.get_env(
        :flyrank_capstone_social_studio,
        :ai_adapter,
        FlyrankCapstoneSocialStudio.Ai.Adapters.GeminiAdapter
      )

    adapter.generate_ab_variants(content, platform_name, profile, opts)
  end
end
