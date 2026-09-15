defmodule FlyrankCapstoneSocialStudioWeb.CampaignController do
  use FlyrankCapstoneSocialStudioWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing

  tags ["Campaigns"]

  operation :show,
    summary: "Get a campaign",
    parameters: [id: [in: :path, type: :integer, required: true, description: "Campaign post ID"]],
    responses: [ok: "Campaign with variants and slots", not_found: "Campaign not found"]

  operation :history,
    summary: "Get publishing history",
    responses: [ok: "Publication attempt audit history"]

  def show(conn, %{"id" => id}) do
    case Content.get_campaign_details(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Campaign post not found"})

      post ->
        conn
        |> put_status(:ok)
        |> render(:show, post: post)
    end
  end

  def history(conn, _params) do
    attempts = Publishing.list_history()

    conn
    |> put_status(:ok)
    |> render(:history, attempts: attempts)
  end
end
