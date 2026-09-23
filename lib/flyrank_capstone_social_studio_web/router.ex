defmodule FlyrankCapstoneSocialStudioWeb.Router do
  use FlyrankCapstoneSocialStudioWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FlyrankCapstoneSocialStudioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ===================================================================
  # Documentation Routes (Scalar UI)
  # ===================================================================
  scope "/api" do
    pipe_through :browser

    get "/scalar", FlyrankCapstoneSocialStudioWeb.ScalarController, :index
  end

  # ===================================================================
  # Application API Endpoints
  # ===================================================================
  scope "/api", FlyrankCapstoneSocialStudioWeb do
    pipe_through :api

    post "/blog-posts", PostController, :create

    # Variant & Campaign Post Management
    patch "/variants/:id", VariantController, :update
    post "/variants/:id/approve", VariantController, :approve
    post "/variants/:id/reject", VariantController, :reject
    post "/variants/:id/schedule", VariantController, :schedule

    # Publishing & History
    post "/slots/:id/publish", SlotController, :publish
    get "/campaigns/:id", CampaignController, :show
    get "/publishing/history", CampaignController, :history

    # System Health
    get "/health", HealthController, :check
  end

  # ===================================================================
  # Browser & Dashboard Routes
  # ===================================================================
  scope "/", FlyrankCapstoneSocialStudioWeb do
    pipe_through :browser
    # Route root directly to ContentLive.Index
    live "/", ContentLive.Index, :index
    live "/posts", ContentLive.Index, :index
    live "/posts/:id", PostLive.Show, :show
    live "/analytics", AnalyticsLive.Index, :index
    # Live_dashboard route for system monitoring
    live_dashboard "/dashboard", metrics: FlyrankCapstoneSocialStudioWeb.Telemetry
  end

  if Application.compile_env(:flyrank_capstone_social_studio, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
