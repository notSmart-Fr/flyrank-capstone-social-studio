defmodule FlyrankCapstoneSocialStudioWeb.PostController do
  use FlyrankCapstoneSocialStudioWeb, :controller

  alias FlyrankCapstoneSocialStudio.Content

  @doc """
  Ingests raw content or URL payloads and generates platform templates idempotently.
  """
  def create(conn, params) do
    post_params = Map.get(params, "post", params)
    platforms = Map.get(params, "platforms", ["telegram", "mock_x", "mock_linkedin"])
    idempotency_key = List.first(get_req_header(conn, "idempotency-key"))

    case Content.ingest_and_template(post_params, platforms, idempotency_key) do
      {:ok, {post, variants}} ->
        conn
        |> put_status(:created)
        |> render(:show_with_variants, post: post, variants: variants)

      {:error, :concurrent_request_in_flight} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "A request with this Idempotency-Key is currently in flight."})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: to_string(reason)})
    end
  end
end
