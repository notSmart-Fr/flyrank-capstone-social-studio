defmodule FlyrankCapstoneSocialStudio.Publishing.Workers.PublishWorker do
  @moduledoc """
  Durable Oban worker for executing slot publication.
  """
  use Oban.Worker, queue: :publishing, max_attempts: 3

  require Logger

  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.PubSub

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"slot_id" => slot_id}}) do
    Logger.info("⚙️ [PUBLISH WORKER] Starting execution for slot_id: #{slot_id}")

    slot = Publishing.get_slot!(slot_id)

    case Publishing.dispatch_slot(slot) do
      {:ok, _attempt} ->
        Logger.info("🚀 [PUBLISH WORKER SUCCESS] Slot #{slot_id} published successfully!")

        # Broadcast 1: Global publishing channel
        Phoenix.PubSub.broadcast(PubSub, "publishing:events", {:slot_published, slot})

        # Broadcast 2: Specific Post channel (for LiveView UI auto-refresh)
        Phoenix.PubSub.broadcast(PubSub, "post:#{slot.variant.post_id}", {:slot_published, slot})

        :ok

      {:error, reason} ->
        error_msg = extract_error_message(reason)

        # 👈 This guarantees the exact error prints directly to your terminal logs!
        Logger.error("❌ [PUBLISH WORKER FAILED] Slot #{slot_id} failed: #{error_msg}")

        # Broadcast failures to both channels
        Phoenix.PubSub.broadcast(PubSub, "publishing:events", {:slot_failed, slot, error_msg})
        Phoenix.PubSub.broadcast(PubSub, "post:#{slot.variant.post_id}", {:slot_failed, slot, error_msg})

        {:error, error_msg}
    end
  end

  # Safely extracts error strings across different return types (structs, atoms, strings)
  defp extract_error_message(%{error_message: msg}) when is_binary(msg), do: msg
  defp extract_error_message(msg) when is_binary(msg), do: msg
  defp extract_error_message(reason), do: inspect(reason)
end
