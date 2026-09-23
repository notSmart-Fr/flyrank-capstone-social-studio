defmodule FlyrankCapstoneSocialStudio.Content.GenerateAiVariants.Core do
  @moduledoc """
  Core domain logic for generating A/B social media variants via Gemini
  and verifying grounding against source text.
  """

  import Ecto.Query

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Content.AiGeneration
  alias FlyrankCapstoneSocialStudio.Content.AiGenerator
  alias FlyrankCapstoneSocialStudio.Content.ConstraintProfile
  alias FlyrankCapstoneSocialStudio.Content.GroundingVerifier
  alias FlyrankCapstoneSocialStudio.Content.Post
  alias FlyrankCapstoneSocialStudio.Repo

  def execute(post_id, platform) do
    post = Content.get_post!(post_id)

    case ConstraintProfile.get(platform) do
      nil ->
        {:error, :unsupported_platform}

      profile ->
        case AiGenerator.generate_ab_variants(post.content, platform, profile) do
          {:ok, result} ->
            # Log financial telemetry independently
            log_ai_generation(post.id, platform, result)

            # Grounding verification
            ground_a = GroundingVerifier.verify_grounding(post.content, result.variant_a)
            ground_b = GroundingVerifier.verify_grounding(post.content, result.variant_b)

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

  defp determine_grounding_status({:ok, :grounded}), do: {"draft", nil}

  defp determine_grounding_status({:error, :hallucination_detected, claims}) do
    {"rejected",
     "Grounding Audit Failed: Fake or unsupported claims detected -> #{Enum.join(claims, ", ")}"}
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

    from(p in Post, where: p.id == ^post_id)
    |> Repo.update_all(inc: [total_ai_cost: result.cost])

    update_post_total_ai_cost(post_id)
  end

  defp update_post_total_ai_cost(post_id) do
    post = Content.get_post!(post_id)
    variants = Content.get_post_variants(post_id)

    total_cost =
      Enum.reduce(variants, Decimal.new("0.0"), fn variant, acc ->
        Decimal.add(acc, variant.generation_cost || Decimal.new("0.0"))
      end)

    Content.update_post(post, %{total_ai_cost: total_cost})
  end
end
