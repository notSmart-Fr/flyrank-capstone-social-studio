defmodule FlyrankCapstoneSocialStudio.Content.GenerateAiVariants.Worker do
  @moduledoc """
  Oban worker for running AI variant generation in the background
  and broadcasting the results to connected LiveViews.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      period: 60,
      fields: [:args],
      keys: [:post_id, :platform],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias FlyrankCapstoneSocialStudio.Content.GenerateAiVariants.Core
  alias Phoenix.PubSub

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => post_id, "platform" => platform}}) do
    case Core.execute(post_id, platform) do
      {:ok, %{variant_a: draft_a, variant_b: draft_b}} ->
        PubSub.broadcast(
          FlyrankCapstoneSocialStudio.PubSub,
          "post:#{post_id}",
          {:ai_generation_complete, %{platform: platform, a: draft_a, b: draft_b}}
        )

        :ok

      {:error, reason} ->
        PubSub.broadcast(
          FlyrankCapstoneSocialStudio.PubSub,
          "post:#{post_id}",
          {:ai_generation_failed, %{platform: platform, reason: inspect(reason)}}
        )

        {:error, reason}
    end
  end
end
