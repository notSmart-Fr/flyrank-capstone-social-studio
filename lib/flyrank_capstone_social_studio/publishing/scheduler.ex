defmodule FlyrankCapstoneSocialStudio.Publishing.Scheduler do
  @moduledoc """
  Durable background worker that polls for due pending slots and dispatches them.
  Resumable across application restarts.
  """
  use GenServer
  import Ecto.Query, warn: false

  alias FlyrankCapstoneSocialStudio.Repo
  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.Publishing.Slot

  @poll_interval :timer.seconds(5)

  @spec start_link() :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    poll_interval = Keyword.get(opts, :poll_interval, @poll_interval)
    schedule_poll(poll_interval)
    {:ok, %{poll_interval: poll_interval}}
  end

  @impl true
  def handle_info(:poll, state) do
    process_due_slots()
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  @doc """
  Queries and processes all pending slots whose scheduled_at timestamp has passed.
  """
  def process_due_slots do
    now = DateTime.utc_now()

    due_slots =
      from(s in Slot,
        where: s.status == "pending" and s.scheduled_at <= ^now
      )
      |> Repo.all()

    Enum.map(due_slots, fn slot ->
      Publishing.dispatch_slot(slot)
    end)
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end
end
