defmodule FlyrankCapstoneSocialStudioWeb.PostController do
  use FlyrankCapstoneSocialStudioWeb, :controller

  alias FlyrankCapstoneSocialStudio.Content

  def create(conn, %{"post" => post_params} = params) do
    platforms = Map.get(params, "platforms", ["telegram", "mock_x", "mock_linkedin"])

    case Content.ingest_and_template(post_params, platforms) do
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
