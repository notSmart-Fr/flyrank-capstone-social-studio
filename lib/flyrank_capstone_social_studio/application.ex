defmodule FlyrankCapstoneSocialStudio.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  @spec start(any(), any()) :: {:error, any()} | {:ok, pid()}
  def start(_type, _args) do
    # 1. Attach Telemetry Handlers FIRST (before Oban initializes)
    :telemetry.attach(
      "global-oban-errors",
      [:oban, :job, :exception],
      fn _event, _measurements, meta, _config ->
        Logger.error(
          "[GLOBAL OBAN CRASH] Worker #{meta.job.worker} failed: #{inspect(meta.reason)}"
        )
      end,
      %{}
    )

    # 2. Define Supervision Tree
    children = [
      FlyrankCapstoneSocialStudioWeb.Telemetry,
      FlyrankCapstoneSocialStudio.Repo,
      {DNSCluster,
       query: Application.get_env(:flyrank_capstone_social_studio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FlyrankCapstoneSocialStudio.PubSub},
      {Finch, name: FlyrankCapstoneSocialStudio.Finch},
      # Start the background worker scheduler
      {Oban, Application.fetch_env!(:flyrank_capstone_social_studio, Oban)},
      # Start to serve requests, typically the last entry
      FlyrankCapstoneSocialStudioWeb.Endpoint
    ]

    # 3. Start Supervisor
    opts = [strategy: :one_for_one, name: FlyrankCapstoneSocialStudio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  @spec config_change(any(), any(), any()) :: :ok
  def config_change(changed, _new, removed) do
    FlyrankCapstoneSocialStudioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
