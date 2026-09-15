defmodule FlyrankCapstoneSocialStudioWeb.PostController do
  use FlyrankCapstoneSocialStudioWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias FlyrankCapstoneSocialStudio.Content

  tags ["Posts"]

  operation :create,
    summary: "Ingest a blog post",
    description: "Ingests source content and generates platform-specific draft variants.",
    request_body: {"Post and target platform parameters", "application/json", %OpenApiSpex.Schema{type: :object}},
    responses: [
      created: "Post and generated variants created",
      unprocessable_entity: "Invalid post or platform parameters"
    ]

  def create(conn, %{"post" => post_params} = params) do
    platforms = Map.get(params, "platforms", ["telegram", "mock_x", "mock_linkedin"])

    case Content.ingest_and_generate(post_params, platforms) do
      {:ok, {post, variants}} ->
        conn
        |> put_status(:created)
        |> render(:show_with_variants, post: post, variants: variants)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end
end
