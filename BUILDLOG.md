# Build Log: Scalar and Docker Setup

## Problem

The Scalar API reference page loaded at `/api/scalar`, but it could not load the OpenAPI document from `/api/openapi.json`. The browser reported a 500 response from the document endpoint:

```text
Failed to load resource: the server responded with a status of 500
Missing private.open_api_spex key in conn
```

After the initial routing issue was addressed, the document endpoint returned successfully but contained an empty `paths` object. Scalar therefore displayed no API operations.

Docker also entered a startup loop while the application attempted to connect to PostgreSQL.

## Root Causes

### 1. OpenAPI plug was missing from documentation routes

The `/api/scalar` and `/api/openapi.json` routes were initially sent through the browser pipeline. That pipeline did not run `OpenApiSpex.Plug.PutApiSpec`, so `OpenApiSpex.Plug.RenderSpec` could not find the OpenAPI module in `conn.private.open_api_spex`.

This caused the following runtime error:

```text
Missing private.open_api_spex key in conn. Check that PutApiSpec is being called in the Conn pipeline
```

### 2. OpenAPI routes had no operation metadata

`ApiSpec` used `Paths.from_router(Router)`, but the API controllers did not define any OpenApiSpex operations. The generated document was valid, but its `paths` object was empty.

### 3. PostgreSQL data volume did not match Compose configuration

The existing Docker volume contained a PostgreSQL 16 data directory, while Compose initially requested PostgreSQL 17. PostgreSQL refused to start with:

```text
The data directory was initialized by PostgreSQL version 16, which is not compatible with this version 17.11.
```

After aligning the image to PostgreSQL 16, the existing cluster still did not contain the configured database `flyrank_capstone_social_studio_dev`. The cluster contained `social_studio` instead, because PostgreSQL initialization variables are only applied when a data directory is created for the first time.

## Solution

### OpenAPI and Scalar

1. Added a dedicated `:docs` router pipeline with:

   ```elixir
   plug :accepts, ["html", "json"]
   plug OpenApiSpex.Plug.PutApiSpec, module: FlyrankCapstoneSocialStudioWeb.ApiSpec
   ```

2. Applied the `:docs` pipeline to `/api/scalar` and `/api/openapi.json`.
3. Removed the scoped module alias from the documentation route so `OpenApiSpex.Plug.RenderSpec` resolves to the external library module.
4. Added `OpenApiSpex.ControllerSpecs` operation definitions to the API controllers:
   - `PostController`
   - `CampaignController`
   - `VariantController`
   - `SlotController`
   - `HealthController`
5. Added operation summaries, tags, path parameters, request body descriptions, and response statuses.

### PostgreSQL and Docker

1. Changed the Compose database image to `postgres:16-alpine` to match the existing volume.
2. Declared the `postgres_data` named volume explicitly.
3. Changed the database health check to run an authenticated SQL query:

   ```yaml
   PGPASSWORD=$$POSTGRES_PASSWORD psql -U $$POSTGRES_USER -d $$POSTGRES_DB -c 'SELECT 1' >/dev/null
   ```

4. Created the missing `flyrank_capstone_social_studio_dev` database in the existing PostgreSQL cluster without deleting the volume.
5. Rebuilt the Phoenix image so the Docker release included the updated router and OpenAPI controller metadata.

## Verification

The generated OpenAPI document now returns HTTP 200 and contains 9 paths:

```text
POST  /api/blog-posts
PATCH /api/campaign-posts/{id}
POST  /api/campaign-posts/{id}/approve
POST  /api/campaign-posts/{id}/reject
POST  /api/campaign-posts/{id}/schedule
GET   /api/campaigns/{id}
GET   /api/health
GET   /api/publishing/history
POST  /api/slots/{id}/publish
```

The Scalar page also returns HTTP 200:

```text
http://localhost:4000/api/scalar
```

The Docker startup now completes database migrations and starts Phoenix successfully.
