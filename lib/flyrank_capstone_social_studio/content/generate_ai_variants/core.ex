defmodule FlyrankCapstoneSocialStudio.Content.GenerateAiVariants.Core do
  @moduledoc """
  Core domain logic for generating A/B social media variants via Gemini
  and verifying factual grounding against source text.
  """

  import Ecto.Query

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Content.AiGeneration
  alias FlyrankCapstoneSocialStudio.Content.AiGenerator
  alias FlyrankCapstoneSocialStudio.Content.ConstraintProfile
  alias FlyrankCapstoneSocialStudio.Content.GroundingVerifier
  alias FlyrankCapstoneSocialStudio.Content.Post
  alias FlyrankCapstoneSocialStudio.Repo

  @doc """
  Executes the A/B variant generation pipeline for a given post and target platform.

  Accepts options (`opts`):
    * `:api_url` - Overrides the Gemini endpoint for test mocking (`Bypass`).
    * `:api_key` - Overrides the Gemini API key.
  """
  @spec execute(integer() | String.t(), String.t(), keyword()) ::
          {:ok, %{variant_a: map(), variant_b: map()}} | {:error, term()}
  def execute(post_id, platform, opts \\ []) do
    post = Content.get_post!(post_id)

    case ConstraintProfile.get(platform) do
      nil ->
        {:error, :unsupported_platform}

      profile ->
        case AiGenerator.generate_ab_variants(post.content, platform, profile, opts) do
          {:ok, result} ->
            # 1. Log financial telemetry independently
            log_ai_generation(post.id, platform, result)

            # 2. Pass runtime opts to GroundingVerifier so test Bypass URLs flow through
            ground_a = GroundingVerifier.verify_grounding(post.content, result.variant_a, opts)
            ground_b = GroundingVerifier.verify_grounding(post.content, result.variant_b, opts)

            {status_a, reason_a} = determine_grounding_status(ground_a)
            {status_b, reason_b} = determine_grounding_status(ground_b)

            draft_a = %{
              id: nil,
              platform: platform,
              variant_label: "A",
              content: result.variant_a,
              status: status_a,
              rejection_reason: reason_a,
              model_used: result.model || "gemini-2.5-flash",
              prompt_tokens: div(result.prompt_tokens, 2),
              completion_tokens: div(result.completion_tokens, 2),
              total_tokens: div(result.prompt_tokens + result.completion_tokens, 2),
              generation_cost: Decimal.div(result.cost, 2)
            }

            draft_b = %{
              id: nil,
              platform: platform,
              variant_label: "B",
              content: result.variant_b,
              status: status_b,
              rejection_reason: reason_b,
              model_used: result.model || "gemini-2.5-flash",
              prompt_tokens: div(result.prompt_tokens, 2),
              completion_tokens: div(result.completion_tokens, 2),
              total_tokens: div(result.prompt_tokens + result.completion_tokens, 2),
              generation_cost: Decimal.div(result.cost, 2)
            }

            {:ok, %{variant_a: draft_a, variant_b: draft_b}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  # Success case (2-tuple)
  defp determine_grounding_status({:ok, :grounded}), do: {"draft", nil}

  # Specific 3-tuple error cases
  defp determine_grounding_status({:error, :hallucination_detected, claims})
       when is_list(claims) do
    {"rejected",
     "Grounding Audit Failed: Fake or unsupported claims detected -> #{Enum.join(claims, ", ")}"}
  end

  defp determine_grounding_status({:error, :audit_failed, reason}) do
    {"needs_review", "Grounding Audit Incomplete: #{reason}"}
  end

  defp log_ai_generation(post_id, platform, result) do
    %AiGeneration{}
    |> AiGeneration.changeset(%{
      post_id: post_id,
      platform: platform,
      model_used: result.model,
      prompt_tokens: result.prompt_tokens,
      completion_tokens: result.completion_tokens,
      total_tokens: result.prompt_tokens + result.completion_tokens,
      cost: result.cost
    })
    |> Repo.insert!()

    # Atomic SQL increment ensures total_ai_cost updates reliably without relying on empty variant tables
    from(p in Post, where: p.id == ^post_id)
    |> Repo.update_all(inc: [total_ai_cost: result.cost])
  end
end
