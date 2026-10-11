defmodule FlyrankCapstoneSocialStudio.Content.Workers.VerifyGroundingWorker do
  @moduledoc """
  Oban worker for asynchronously verifying factual grounding of a variant
  against its source post content.

  Guaranteed idempotent via Oban `unique` constraint across variant_id.
  Broadcasts results via PubSub to update connected LiveViews in real time.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      period: 60,
      fields: [:args],
      keys: [:variant_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias FlyrankCapstoneSocialStudio.Content
  alias Phoenix.PubSub

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"variant_id" => variant_id}}) do
    variant = Content.get_variant!(variant_id)

    case Content.verify_variant_grounding(variant) do
      {:ok, updated_variant} ->
        PubSub.broadcast(
          FlyrankCapstoneSocialStudio.PubSub,
          "grounding:events",
          {:grounding_verified, updated_variant}
        )

        PubSub.broadcast(
          FlyrankCapstoneSocialStudio.PubSub,
          "post:#{variant.post_id}",
          {:grounding_verified, updated_variant}
        )

        :ok

      {:error, reason} ->
        PubSub.broadcast(
          FlyrankCapstoneSocialStudio.PubSub,
          "grounding:events",
          {:grounding_verification_failed, %{variant_id: variant_id, reason: inspect(reason)}}
        )

        PubSub.broadcast(
          FlyrankCapstoneSocialStudio.PubSub,
          "post:#{variant.post_id}",
          {:grounding_verification_failed, %{variant_id: variant_id, reason: inspect(reason)}}
        )

        {:error, reason}
    end
  end
end
