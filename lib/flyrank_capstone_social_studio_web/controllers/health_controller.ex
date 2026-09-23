# Health check controller for the Social Studio application. Provides an endpoint to verify database connectivity and overall service health.
defmodule FlyrankCapstoneSocialStudioWeb.HealthController do
  use FlyrankCapstoneSocialStudioWeb, :controller

  alias FlyrankCapstoneSocialStudio.Repo

  def check(conn, _params) do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1") do
      {:ok, _} ->
        json(conn, %{status: "ok", database: "connected", timestamp: DateTime.utc_now()})

      {:error, _} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", database: "disconnected", timestamp: DateTime.utc_now()})
    end
  end
end
