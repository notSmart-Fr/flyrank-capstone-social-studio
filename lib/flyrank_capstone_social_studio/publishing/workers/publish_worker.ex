defmodule FlyrankCapstoneSocialStudio.Publishing.Workers.PublishWorker do
  @moduledoc """
  Durable Oban worker for executing slot publication.
  """
  use Oban.Worker, queue: :publishing, max_attempts: 3

  alias FlyrankCapstoneSocialStudio.Publishing

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"slot_id" => slot_id}}) do
    slot = Publishing.get_slot!(slot_id)

    case Publishing.dispatch_slot(slot) do
      {:ok, _attempt} ->
        :ok

      {:error, attempt} ->
        {:error, attempt.error_message || "Publishing failed"}
    end
  end
end
