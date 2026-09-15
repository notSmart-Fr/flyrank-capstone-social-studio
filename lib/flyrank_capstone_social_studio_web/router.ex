defmodule FlyrankCapstoneSocialStudioWeb.Router do
  use FlyrankCapstoneSocialStudioWeb, :router

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
end

  scope "/", FlyrankCapstoneSocialStudioWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", FlyrankCapstoneSocialStudioWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:flyrank_capstone_social_studio, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FlyrankCapstoneSocialStudioWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
