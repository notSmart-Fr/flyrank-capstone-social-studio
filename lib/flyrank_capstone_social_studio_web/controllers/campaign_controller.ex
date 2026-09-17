defmodule FlyrankCapstoneSocialStudioWeb.CampaignController do
  use FlyrankCapstoneSocialStudioWeb, :controller


  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing



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
