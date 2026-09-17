# Social Studio - Multi-Platform Content Ingestion & Publishing Studio

Social Studio is an Elixir/Phoenix API that ingests long-form blog content, generates platform-tailored social media drafts (Telegram, Mock X, Mock LinkedIn), enforces strict constraint rules, provides a human review workflow, and dispatches posts using an idempotent, durable background worker.

---

## Architecture Overview

- **`Content` Context:** Manages raw blog post ingestion, variant generation, and constraint profile validation.
- **`Publishing` Context:** Manages scheduling slots, Oban durable workers, platform publisher adapters, and idempotency checks.

## System Architecture & Workflow

The platform handles content lifecycle management through a decoupled pipeline: **Ingestion & Variant Drafting** $\rightarrow$ **Editorial Lifecycle** $\rightarrow$ **Scheduling** $\rightarrow$ **Idempotent Dispatch Execution**.

```text
┌────────────────────────────────────────────────────────────────────────┐
│ 1. INGESTION & DEDUPLICATION                                           │
│  Payload (Markdown/URL) ──> Content Hash (SHA-256) ──> 5-min Check      │
│                                ├── Match Found ──> Return Existing     │
│                                └── New Content ──> Create Post + AI    │
└────────────────────────────────────────────────────────────────────────┘
│
▼
┌────────────────────────────────────────────────────────────────────────┐
│ 2. EDITORIAL LIFECYCLE                                                 │
│  Draft Variants (A/B) ──> Reviewer Action (Approve / Edit / Reject)   │
└────────────────────────────────────────────────────────────────────────┘
│ (Only Approved)
▼
┌────────────────────────────────────────────────────────────────────────┐
│ 3. SCHEDULING (Auto / Manual)                                          │
│  Mode Calculation ──> Validate Future Timestamp ──> DB Idempotency Key │
└────────────────────────────────────────────────────────────────────────┘
│
▼
┌────────────────────────────────────────────────────────────────────────┐
│ 4. DISPATCH EXECUTION (Oban Worker)                                    │
│  Oban Polls DB ──> Check PublishAttempts ──> External Social API Call  │
└────────────────────────────────────────────────────────────────────────┘
```

---

### Pipeline Breakdown

#### 1. Ingestion & Variant Generation (`Content.ingest_and_generate/2`)
* **Happy Path:**
  1. Client sends a source blog post payload (raw Markdown or URL) and target platform list (`["telegram", "mock_x", "mock_linkedin"]`).
  2. A deterministic SHA-256 hash (`content_hash`) is computed from `title` and `content`.
  3. System calls Gemini AI to generate platform-tailored A/B variants, records token metrics (`prompt_tokens`, `completion_tokens`), and calculates USD generation costs.
  4. Post record is updated with total aggregated campaign AI cost inside a transaction.
* **Failure & Edge Case Handling:**
  * **5-Minute Deduplication Window:** If an identical request arrives within 5 minutes, the query matches `content_hash` and short-circuits—returning existing `%Post{}` and `%Variant{}` records without regenerating or spending AI tokens.
  * **AI Rate Limit / API Error:** If variant generation fails mid-stream for any platform, the Ecto transaction rolls back, preventing partial or orphaned post creations.

#### 2. Editorial Lifecycle (`Content.Variant`)
* **Happy Path:**
  * Variants enter the system in `"draft"` status.
  * Reviewers can edit content (`PATCH /api/variants/:id`) or approve it (`POST /api/variants/:id/approve`), transitioning status to `"approved"`.
* **Failure & Edge Case Handling:**
  * **Unapproved Scheduling Block:** Only variants in `"approved"` state can be scheduled. Attempting to schedule a `"draft"` or `"rejected"` variant returns `{:error, :unapproved_variant}` (`403 Forbidden`).

#### 3. Scheduling (`Publishing.schedule_variant/3`)
* **Happy Path:**
  * Supports two modes:
    * `:manual` — Uses explicit user-provided ISO-8601 timestamp.
    * `:auto` — Queries latest DB slots for the target platform and automatically schedules 2 hours past the highest existing slot time.
  * Validates that `scheduled_at` is set in the future (with a 60-second execution buffer).
  * Persists `%Slot{status: "pending"}` and enqueues a background Oban job scheduled for execution at `slot.scheduled_at`.
* **Failure & Edge Case Handling:**
  * **Rapid Double-Submit (API Level):** Uses PostgreSQL unique index on `slots.idempotency_key`. Duplicate requests hit the unique constraint and fail gracefully with `{:error, changeset}`.
  * **Concurrent Scheduling (No Key):** Runs inside a SQL transaction with a row-level `FOR UPDATE` lock on the `%Variant{}` to eliminate race conditions.
  * **Failed Slot Retries:** If scheduling targets a previously failed slot (`status: "failed"`), the context resets its status to `"pending"`, updates `scheduled_at`, and re-enqueues the Oban job rather than accumulating dead records.

#### 4. Idempotent Dispatch Execution (`PublishWorker` & `Dispatcher`)
* **Happy Path:**
  1. Oban picks up the scheduled job when `NOW() >= slot.scheduled_at`.
  2. The `Dispatcher` makes an HTTP request to the target platform adapter (e.g., Telegram, X).
  3. On success, a `%PublishAttempt{status: "success"}` log is written, and the slot updates to `"published"`.
* **Failure & Edge Case Handling:**
  * **Post-Execution Network Drops (Zone 2 Failure):** If an external API processes the post but the network connection drops before returning `200 OK`, Oban will retry the worker.
  * **Duplicate Prevention:** Before dispatching, `Dispatcher.dispatch_slot/2` queries `publish_attempts` for a prior successful record for that `slot_id`. If found, it short-circuits immediately with `{:ok, attempt}`—preventing double-posting on external social networks.
  * **Retry Backoff:** Uncaught network failures trigger Oban’s exponential backoff retry mechanism until max retries are reached, at which point the slot transitions to `"failed"`.

---

## Quick Start (Docker)

### Prerequisites

- Docker Desktop with Docker Compose
- Ports `4000` and `5432` available

### Start the Application

From the repository root, build the Phoenix image and start PostgreSQL and the API:

```bash
docker compose up --build
```

Compose starts the `db` service first and waits for PostgreSQL to become healthy before starting the `web` service. PostgreSQL runs inside Docker; no separate PostgreSQL installation is required on the host. The API will then be available at `http://localhost:4000`.

To start the services in the background:

```bash
docker compose up --build -d
```

Check the service status and follow application logs with:

```bash
docker compose ps
docker compose logs -f web
```

To stop the containers while keeping the PostgreSQL data volume:

```bash
docker compose down
```

To stop the containers and remove the PostgreSQL data volume, useful for a clean database reset:

```bash
docker compose down -v
```

The Compose configuration provides the database URL, Phoenix port, and database migrations automatically. Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in a `.env` file in the repository root when using the live Telegram adapter.

## API Endpoints

| Method | Endpoint | Description |
| --- | --- | --- |
| `POST` | `/api/blog-posts` | Ingests a blog post and generates draft variants. |
| `GET` | `/api/campaigns/:id` | Returns a campaign post with variants and slots. |
| `PATCH` | `/api/campaign-posts/:id` | Edits variant content. |
| `POST` | `/api/campaign-posts/:id/approve` | Approves a variant for scheduling. |
| `POST` | `/api/campaign-posts/:id/reject` | Rejects a variant with a reason. |
| `POST` | `/api/campaign-posts/:id/schedule` | Schedules an approved variant. |
| `POST` | `/api/slots/:id/publish` | Triggers immediate idempotent dispatch. |
| `GET` | `/api/publishing/history` | Returns the audit trail of publication attempts. |
## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.