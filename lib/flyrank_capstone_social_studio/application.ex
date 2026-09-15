defmodule FlyrankCapstoneSocialStudio.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FlyrankCapstoneSocialStudioWeb.Telemetry,
      FlyrankCapstoneSocialStudio.Repo,
      {DNSCluster,
       query: Application.get_env(:flyrank_capstone_social_studio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FlyrankCapstoneSocialStudio.PubSub},
      # Start the background worker scheduler
      FlyrankCapstoneSocialStudio.Publishing.Scheduler,
      # {FlyrankCapstoneSocialStudio.Worker, arg},
      # Start to serve requests, typically the last entry
      FlyrankCapstoneSocialStudioWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FlyrankCapstoneSocialStudio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FlyrankCapstoneSocialStudioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
