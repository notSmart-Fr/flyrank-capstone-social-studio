defmodule FlyrankCapstoneSocialStudioWeb.ApiSpec do
  alias OpenApiSpex.{Info, OpenApi, Paths, Server}
  alias FlyrankCapstoneSocialStudioWeb.Router

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        %Server{url: System.get_env("API_URL", "http://localhost:4000")}
      ],
      info: %Info{
        title: "Flyrank Capstone Social Studio API",
        version: "1.0.0",
        description: "API documentation for managing blog posts, campaign variants, and social publishing slots."
      },
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
