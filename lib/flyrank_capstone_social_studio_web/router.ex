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
    plug OpenApiSpex.Plug.PutApiSpec, module: FlyrankCapstoneSocialStudioWeb.ApiSpec
  end

  pipeline :docs do
    plug :accepts, ["html", "json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: FlyrankCapstoneSocialStudioWeb.ApiSpec
  end

  # ===================================================================
  # Documentation Routes (Scalar UI & Dynamic Spec JSON)
  # ===================================================================
  scope "/api" do
    pipe_through :docs

    get "/scalar", FlyrankCapstoneSocialStudioWeb.ScalarController, :index
    # Pass module directly in the plug opts so RenderSpec doesn't rely on conn.private
    get "/openapi.json", Elixir.OpenApiSpex.Plug.RenderSpec,
      module: FlyrankCapstoneSocialStudioWeb.ApiSpec
  end

  # ===================================================================
  # Application API Endpoints
  # ===================================================================
  scope "/api", FlyrankCapstoneSocialStudioWeb do
    pipe_through :api

    post "/blog-posts", PostController, :create
    patch "/campaign-posts/:id", VariantController, :update
    post "/campaign-posts/:id/approve", VariantController, :approve
    post "/campaign-posts/:id/reject", VariantController, :reject
    post "/campaign-posts/:id/schedule", VariantController, :schedule
    post "/slots/:id/publish", SlotController, :publish
    get "/campaigns/:id", CampaignController, :show
    get "/publishing/history", CampaignController, :history
    get "/health", HealthController, :check
  end

  # ===================================================================
  # Browser & Dashboard Routes
  # ===================================================================
  scope "/", FlyrankCapstoneSocialStudioWeb do
    pipe_through :browser

    live "/", StudioLive
    live_dashboard "/dashboard", metrics: FlyrankCapstoneSocialStudioWeb.Telemetry
  end

  if Application.compile_env(:flyrank_capstone_social_studio, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
