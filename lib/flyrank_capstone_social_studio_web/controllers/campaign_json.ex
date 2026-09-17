defmodule FlyrankCapstoneSocialStudioWeb.CampaignJSON do
  def show(%{post: post}) do
    %{
      data: %{
        id: post.id,
        title: post.title,
        content: post.content,
        source_type: post.source_type,
        inserted_at: post.inserted_at,
        variants: Enum.map(post.variants, &variant_with_slots/1)
      }
    }
  end

  def history(%{attempts: attempts}) do
    %{
      data: Enum.map(attempts, &attempt_data/1)
    }
  end

  defp variant_with_slots(variant) do
    %{
      id: variant.id,
      platform: variant.platform,
      content: variant.content,
      status: variant.status,
      character_count: variant.character_count,
      hashtags_count: variant.hashtags_count,
      rejection_reason: variant.rejection_reason,
      slots: Enum.map(variant.slots || [], fn slot ->
        %{
          id: slot.id,
          scheduled_at: slot.scheduled_at,
          status: slot.status,
          idempotency_key: slot.idempotency_key
        }
      end)
    }
  end

  defp attempt_data(attempt) do
    raw_response = Map.get(attempt.response_payload || %{}, "raw_response")
    %{
      id: attempt.id,
      slot_id: attempt.slot_id,
      platform: get_in(attempt, [Access.key(:slot), Access.key(:variant), Access.key(:platform)]),
      status: attempt.status,
      attempted_at: attempt.inserted_at,
      external_post_id: attempt.external_post_id,
      error_message: attempt.error_message,
      raw_response: raw_response
    }
  end
end
