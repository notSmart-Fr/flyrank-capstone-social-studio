defmodule FlyrankCapstoneSocialStudioWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `%Plug.Conn{}` responses.

  See `Phoenix.Controller.action_fallback/1`.
  """
  use FlyrankCapstoneSocialStudioWeb, :controller

  # This clause matches Ecto changeset errors
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: FlyrankCapstoneSocialStudioWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  # This clause matches custom atom or string error reasons
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(
      html: FlyrankCapstoneSocialStudioWeb.ErrorHTML,
      json: FlyrankCapstoneSocialStudioWeb.ErrorJSON
    )
    |> render(:"404")
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: to_string(reason)})
  end
end
