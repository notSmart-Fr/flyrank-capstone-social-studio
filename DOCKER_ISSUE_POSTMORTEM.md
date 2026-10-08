# Docker Issue Postmortem: `/app/bin/migrate: not found` (Exit Code 127)

## 1. Problem Description

When starting the application stack via `docker compose up`, the Postgres database container initialized and became healthy, but the Phoenix web service container immediately crashed with:

```text
db-1   | 2026-10-08 03:49:58.345 UTC [1] LOG:  database system is ready to accept connections
Container flyrank-socialmedia-studio-db-1 Healthy 
web-1  | sh: 1: /app/bin/migrate: not found
web-1 exited with code 127
```

---

## 2. Root Cause Analysis

1. **Docker Command Flow**:
   In `docker-compose.yml`, the `web` container defines:
   ```yaml
   command: ["sh", "-c", "/app/bin/migrate && /app/bin/server"]
   ```

2. **File Presence vs. Execution Failure**:
   * Inspecting `/app/bin` inside the built Docker image showed that `/app/bin/migrate` was indeed present and had executable permissions (`-rwxr-xr-x`).
   * However, executing `/app/bin/migrate` under Linux shell failed with `sh: 1: /app/bin/migrate: not found`.

3. **Carriage Return in Shebang (`\r\n`)**:
   * Because the repository was cloned or checked out on a Windows host, the scripts in `rel/overlays/bin/` (`migrate` and `server`) were formatted with Windows CRLF (`\r\n`) line terminators.
   * In a Linux container (Debian-based), the kernel reads the shebang line `#!/bin/sh\r`.
   * The kernel searches for an interpreter binary literally named `/bin/sh\r`. Because `/bin/sh\r` does not exist, the shell returns the misleading error `sh: 1: /app/bin/migrate: not found` with exit code `127` (Command Not Found).

---

## 3. Resolution Steps

### Step 1: Converted Scripts to Unix Line Endings (LF)
The CRLF line endings were stripped from the release wrapper scripts:
* `rel/overlays/bin/migrate`
* `rel/overlays/bin/server`

### Step 2: Added `.gitattributes`
A `.gitattributes` file was created in the project root to ensure Git always checks out scripts with Unix LF line endings regardless of operating system configuration:
```gitattributes
* text=auto eol=lf
*.sh text eol=lf
rel/overlays/bin/* text eol=lf
Dockerfile text eol=lf
```

### Step 3: Hardened `Dockerfile` Against Line Endings & Permissions
To prevent this issue from ever recurring when building Docker images on any Windows host, defensive steps were added to `Dockerfile`:

1. **Builder Stage (before `mix release`)**:
   ```dockerfile
   # Copy runtime config and release setup
   COPY config/runtime.exs config/
   COPY rel rel
   RUN chmod -R +x rel/overlays/bin && sed -i 's/\r$//' rel/overlays/bin/*
   RUN mix release
   ```

2. **Final Runner Stage (before dropping privileges to `USER nobody`)**:
   ```dockerfile
   # Copy compiled release
   COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/flyrank_capstone_social_studio ./
   RUN chmod -R +x /app/bin && sed -i 's/\r$//' /app/bin/*

   USER nobody
   ```

---

## 4. Verification & Results

1. **Docker Build**:
   ```bash
   docker compose build web
   ```
   Built successfully with sanitized scripts.

2. **Service Startup & Migrations**:
   ```bash
   docker compose up -d
   ```
   Logs confirmed all Ecto migrations executed cleanly:
   ```text
   web-1  | [info] execute "COMMENT ON TABLE \"public\".oban_jobs IS '14'"
   web-1  | [info] == Migrated 20260916070859 in 0.0s
   web-1  | [info] == Running 20260917065722 FlyrankCapstoneSocialStudio.Repo.Migrations.AddAiCostTrackingToVariantsAndPosts.change/0 forward
   ...
   web-1  | [info] Running FlyrankCapstoneSocialStudioWeb.Endpoint with Bandit 1.12.5 at :::4000 (http)
   ```

3. **HTTP Endpoint Verification**:
   * Requesting `http://localhost:4000` returned `StatusCode: 200 OK`.
   * Both `flyrank-socialmedia-studio-db-1` and `flyrank-socialmedia-studio-web-1` containers are running and healthy.

