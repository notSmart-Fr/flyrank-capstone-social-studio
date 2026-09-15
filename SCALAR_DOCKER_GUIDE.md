# Scalar and Docker Setup Guide for Phoenix

This guide explains how to expose an OpenAPI document through OpenApiSpex, render it with Scalar, and run the application reliably in Docker. It is based on the Social Studio implementation and is intended as a reference for future Phoenix projects.

## 1. The Request Flow

Scalar is only the user interface. It does not generate the API definition.

The complete flow is:

```text
Browser
  |
  | GET /api/scalar
  v
Phoenix ScalarController
  |
  | HTML contains data-url="/api/openapi.json"
  v
Scalar JavaScript
  |
  | GET /api/openapi.json
  v
OpenApiSpex.Plug.PutApiSpec
  |
  | Places the ApiSpec module in conn.private.open_api_spex
  v
OpenApiSpex.Plug.RenderSpec
  |
  v
JSON OpenAPI document
```

There are two separate requests:

1. `/api/scalar` returns the HTML shell and loads the Scalar JavaScript bundle.
2. `/api/openapi.json` returns the OpenAPI document that Scalar renders.

A successful Scalar HTML response does not prove that the OpenAPI document works. Always test both URLs.

## 2. Required Phoenix Pieces

### 2.1 Define an API specification module

The specification module should implement the OpenApiSpex behaviour and build paths from the Phoenix router:

```elixir
defmodule MyAppWeb.ApiSpec do
  alias OpenApiSpex.{Info, OpenApi, Paths, Server}
  alias MyAppWeb.Router

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        %Server{url: System.get_env("API_URL", "http://localhost:4000")}
      ],
      info: %Info{
        title: "My API",
        version: "1.0.0",
        description: "API documentation"
      },
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
```

The `servers` URL is important. It is the base URL Scalar uses for Try It requests. It must match the URL that the browser can actually reach.

### 2.2 Add OpenAPI metadata to controllers

`Paths.from_router/1` can see Phoenix routes, but it needs operation metadata to produce useful path definitions. Each documented controller should use `OpenApiSpex.ControllerSpecs` and declare an `operation`:

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  use OpenApiSpex.ControllerSpecs

  tags ["Users"]

  operation :show,
    summary: "Get a user",
    parameters: [
      id: [in: :path, type: :integer, required: true, description: "User ID"]
    ],
    responses: [
      ok: "User returned",
      not_found: "User not found"
    ]

  def show(conn, %{"id" => id}) do
    # Controller implementation
  end
end
```

Without these declarations, the generated JSON can still be valid but contain:

```json
"paths": {}
```

That means Scalar has no API operations to display.

For request bodies and reusable schemas, prefer named `OpenApiSpex.Schema` modules instead of anonymous object schemas as the API grows. This gives Scalar useful field-level documentation and creates reusable entries under `components.schemas`.

## 3. Phoenix Router Configuration

Use a dedicated documentation pipeline. The important ordering is that `PutApiSpec` runs before `RenderSpec`:

```elixir
pipeline :docs do
  plug :accepts, ["html", "json"]
  plug OpenApiSpex.Plug.PutApiSpec, module: MyAppWeb.ApiSpec
end

scope "/api" do
  pipe_through :docs

  get "/scalar", MyAppWeb.ScalarController, :index
  get "/openapi.json", OpenApiSpex.Plug.RenderSpec,
    module: MyAppWeb.ApiSpec
end
```

The application API pipeline can use JSON only:

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug OpenApiSpex.Plug.PutApiSpec, module: MyAppWeb.ApiSpec
end
```

The `PutApiSpec` plug is required for `RenderSpec`. If it is missing, the request fails with:

```text
Missing private.open_api_spex key in conn
```

A common Phoenix aliasing problem occurs when an external module is placed inside a scoped router such as:

```elixir
scope "/api", MyAppWeb do
```

If the compiler resolves `OpenApiSpex.Plug.RenderSpec` as `MyAppWeb.OpenApiSpex.Plug.RenderSpec`, remove the alias from the documentation scope and use fully qualified controller modules.

## 4. Scalar HTML Controller

A minimal Scalar controller can use the browser's same-origin path for the document:

```elixir
def index(conn, _params) do
  conn
  |> put_resp_content_type("text/html")
  |> html("""
  <!doctype html>
  <html>
    <head>
      <title>API Reference</title>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
    </head>
    <body>
      <script
        id="api-reference"
        data-url="/api/openapi.json">
      </script>
      <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
    </body>
  </html>
  """)
end
```

Using `/api/openapi.json` instead of a hard-coded host keeps the browser request same-origin and avoids unnecessary CORS configuration.

For production, decide whether loading Scalar from a public CDN is acceptable. For a controlled or offline deployment, vendor the Scalar JavaScript asset into the application and serve it through Phoenix static assets instead.

## 5. Local Docker Setup

The local development model is:

```text
localhost:4000 -> Phoenix web container
localhost:5432 -> PostgreSQL container
web container -> db:5432
```

The browser must use `localhost:4000`. The Phoenix container must use the Compose service name `db`, not `localhost`, for its database connection.

Example local environment values:

```text
API_URL=http://localhost:4000
DATABASE_URL=ecto://postgres:postgrespassword@db:5432/flyrank_capstone_social_studio_dev
PHX_HOST=localhost
PORT=4000
PHX_SERVER=true
```

Start the stack from the repository root:

```powershell
docker compose up --build
```

Or run it in the background:

```powershell
docker compose up --build -d
```

Verify the services:

```powershell
docker compose ps
docker compose logs -f web
```

Verify both documentation endpoints:

```powershell
Invoke-WebRequest -UseBasicParsing http://localhost:4000/api/scalar
Invoke-WebRequest -UseBasicParsing http://localhost:4000/api/openapi.json
```

Inspect the generated paths:

```powershell
$document = (Invoke-WebRequest -UseBasicParsing http://localhost:4000/api/openapi.json).Content | ConvertFrom-Json
$document.paths.PSObject.Properties.Name
```

The database health check should authenticate against the configured database. A readiness-only check such as `pg_isready -U postgres` can report that PostgreSQL is alive even when the application password or database name is wrong.

## 6. PostgreSQL Volumes and Version Changes

PostgreSQL environment variables such as `POSTGRES_PASSWORD` and `POSTGRES_DB` are initialization variables. They are applied only when the data directory is empty.

Changing them in Compose does not change an existing database cluster.

The PostgreSQL image major version must match the data directory. For example, a PostgreSQL 16 volume cannot be mounted directly into PostgreSQL 17:

```text
The data directory was initialized by PostgreSQL version 16, which is not compatible with this version 17.
```

For disposable local data, reset the stack with:

```powershell
docker compose down -v
docker compose up --build
```

This deletes the database volume. Do not use `down -v` for data that must be preserved.

For real data, use a PostgreSQL upgrade procedure such as `pg_dump`/`pg_restore` or `pg_upgrade`. Do not solve a major-version mismatch by deleting the volume.

## 7. Local versus Production

| Concern | Local Docker | Production |
| --- | --- | --- |
| Browser URL | `http://localhost:4000` | `https://api.example.com` |
| OpenAPI `servers` URL | `API_URL=http://localhost:4000` | `API_URL=https://api.example.com` |
| TLS | Usually terminated nowhere; plain HTTP is acceptable locally | Terminate TLS at a reverse proxy or load balancer |
| Phoenix listener | HTTP on port 4000 | Private HTTP listener behind the proxy, or HTTPS when directly exposed |
| Database host | Compose service name `db` | Managed/private database hostname |
| Secrets | Local `.env` or Compose-only values | Secret manager or deployment environment; never commit secrets |
| Database volume | Named local Docker volume | Managed database with backups and retention |
| Scalar exposure | Conveniently public on localhost | Restrict, authenticate, or disable if the API is private |
| Static assets | CDN may be acceptable | Prefer pinned, controlled, or vendored assets |

### Local configuration

The local OpenAPI server should be:

```text
http://localhost:4000
```

Do not use `https://localhost` unless the local Phoenix endpoint actually has TLS configured and a trusted certificate.

### Production configuration

Set the public URL that users and Scalar can reach:

```text
API_URL=https://api.example.com
PHX_HOST=api.example.com
PORT=4000
```

If a reverse proxy terminates TLS, Phoenix can still listen on HTTP internally. The proxy must forward the request to the Phoenix port and preserve the correct host/protocol headers according to the deployment's proxy configuration.

Do not set `API_URL` to the internal Docker address such as `http://web:4000`; a browser outside the Compose network cannot resolve or reach that hostname.

## 8. Security Checklist

- Do not commit `SECRET_KEY_BASE`, database passwords, bot tokens, or production credentials.
- Replace development secrets in Compose with environment injection or a secret manager.
- Do not expose PostgreSQL port `5432` publicly in production unless there is a deliberate network/security reason.
- Restrict `/api/scalar` and `/api/openapi.json` if the API contract reveals sensitive internal behavior.
- Protect state-changing API routes with authentication and authorization before production exposure.
- Use HTTPS in production and set secure cookie/session settings.
- Pin or vendor the Scalar JavaScript dependency if supply-chain control is required.
- Keep the OpenAPI document free of real credentials, tokens, private hostnames, and sensitive examples.
- Validate request bodies and response schemas instead of documenting them as unconstrained objects forever.
- Keep database backups and test restoration procedures.
- Avoid `docker compose down -v` except when intentionally destroying disposable local data.

## 9. Troubleshooting

### Scalar page returns 200 but the document returns 500

Check the Phoenix logs. If the error says:

```text
Missing private.open_api_spex key in conn
```

make sure the documentation route uses a pipeline containing `PutApiSpec` before `RenderSpec`.

### OpenAPI document returns 200 but `paths` is empty

Add `use OpenApiSpex.ControllerSpecs` and an `operation` declaration for each controller action. Confirm the action name matches the router action.

### Scalar requests `https://localhost/api/...` and connection is refused

Inspect `document.servers[0].url`. It must include the correct scheme, hostname, and port. For local Docker, use:

```text
http://localhost:4000
```

### PostgreSQL says the data directory has the wrong major version

Use the matching PostgreSQL image, or perform a proper database upgrade. Do not mount a PostgreSQL 16 data directory into PostgreSQL 17.

### PostgreSQL is healthy but Phoenix cannot connect

Check all three values together:

```text
DATABASE_URL username
DATABASE_URL password
DATABASE_URL database name
```

Then compare them with the database cluster. Remember that `POSTGRES_*` initialization values do not modify an existing volume.

## 10. Repeatable Verification Checklist

Run these checks after changing Scalar, OpenApiSpex, Docker, or endpoint configuration:

```powershell
mix compile
docker compose config
docker compose up --build -d
docker compose ps
Invoke-WebRequest -UseBasicParsing http://localhost:4000/api/scalar
Invoke-WebRequest -UseBasicParsing http://localhost:4000/api/openapi.json
```

Then confirm:

- `/api/scalar` returns HTTP 200.
- `/api/openapi.json` returns HTTP 200.
- The JSON `servers[0].url` is reachable from the browser.
- The JSON `paths` object contains the expected API routes.
- Scalar's Try It requests target the correct scheme and port.
- Phoenix logs show successful migrations and no repeated database authentication failures.
