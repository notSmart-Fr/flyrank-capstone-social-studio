defmodule FlyrankCapstoneSocialStudioWeb.PageController do
  use FlyrankCapstoneSocialStudioWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
