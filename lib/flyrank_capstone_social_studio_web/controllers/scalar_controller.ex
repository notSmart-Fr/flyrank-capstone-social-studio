defmodule FlyrankCapstoneSocialStudioWeb.ScalarController do
  use FlyrankCapstoneSocialStudioWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> html("""
    <!doctype html>
    <html>
      <head>
        <title>API Reference - Scalar</title>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </head>
      <body>
        <script
          id="api-reference"
          data-url="/openapi.yaml">
        </script>
        <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
      </body>
    </html>
    """)
  end
end
