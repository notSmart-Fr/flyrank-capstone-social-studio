# BUILDLOG: Engineering Journey & AI Usage Log

> **FlyRank Capstone Brief Section 8 Rule:**  
> *"Your AI-usage log: where AI helped, where it was wrong, what you changed. Honesty is graded, perfection is not. You must be able to explain each line of your code."*

---

## 1. Executive Summary & Tooling Used

* **Primary AI Coding Assistant:** Antigravity / Gemini 2.5 Flash
* **Core Stack:** Elixir 1.20, Phoenix 1.8 (LiveView), Ecto / PostgreSQL, Oban 2.18, Tailwind CSS v4, Docker Compose
* **Development Methodology:** Spec-first architectural design, test-driven validation (TDD with 77 ExUnit tests), and containerized deployment.

---

## 2. Where AI Helped

### A. Architectural Scaffolding & Phoenix 1.8 Idioms
* **LiveView Streams & Layouts:** Rapidly set up Phoenix v1.8 LiveViews using proper `<Layouts.app flash={@flash}>`, avoiding obsolete Phoenix template conventions.
* **OpenAPI 3.0 / Scalar Specs:** Generated type-safe `OpenApiSpex` controller operation schemas for the REST endpoints (`PostController`, `CampaignController`, `VariantController`, `SlotController`, `HealthController`).
* **Tailwind Component Composition:** Built clean, modern UI components for the LiveView Inspector and Analytics dashboard without daisyUI dependencies.

### B. Oban & Asynchronous Telemetry
* **Job Definitions:** Structured idempotent Oban workers (`PublishWorker` and `VerifyGroundingWorker`) with strict concurrency and deduplication keys.
* **Exact Financial Accounting:** Drafted Decimal-based arithmetic logic in `FlyrankCapstoneSocialStudio.Ai.Adapters.GeminiAdapter` to prevent floating-point drift when converting `promptTokenCount` and `candidatesTokenCount` into dollar values.

### C. ExUnit Test Suite Generation
* Generated comprehensive test cases covering tricky edge cases:
  * Platform character and hashtag constraint violations.
  * Attempting to schedule unapproved variants (403 HTTP boundary tests).
  * Rate-limited `Retry-After` snooze calculations for Oban.

---

## 3. Where AI Was Wrong & Hallucinations Encountered

### A. State Machine & Review Workflow Oversights
* **The Issue:** The AI initially assumed any edit on a variant should transition directly to `"accepted"` or remain in `"needs_review"`, leaving users unable to approve or schedule edited variants.
* **The Fix:** We aligned the domain with the Capstone requirements: only valid transitions exist (`draft`, `approved`, `rejected`, `published`, and `needs_review` for audit timeouts). When a human editor manually updates a rejected or review-flagged variant, it returns to `"draft"` so it can be re-evaluated and approved.

### B. Concurrency Test Collisions & KeyError in Analytics
* **KeyError on Post Struct:** When building the Ingestion Cost Ledger on the Analytics dashboard, the AI referenced `post.content_hash` before verifying if `:content_hash` was properly added to the `Post` schema and migration, causing a runtime `KeyError 500`.
* **Idempotency Race Conditions:** The AI initially used non-unique random keys in concurrent idempotency tests, occasionally causing test flakiness against PostgreSQL's unique constraint indexes.
* **Platform Inclusions in Tests:** When generating unit tests for analytics, the AI used `"twitter"` instead of the configured platform atom `"mock_x"`, triggering changeset inclusion errors.

### C. OpenAPI Specification & Scalar Integration
* **The Issue:** The AI originally attempted to use dynamic runtime reflection with `OpenApiSpex`, which caused pipeline conflicts and schema drift against the async event-driven architecture.
* **The Fix:** Shifted to a dedicated, accurate static OpenAPI 3.0 specification (`priv/static/openapi.yaml`) served directly to the Scalar API reference UI at `/api/scalar`. This guarantees exact synchronization with the REST entrypoints while avoiding runtime reflection overhead.

### D. Oban Telemetry Metadata Nesting
* **The Issue:** The AI added Oban telemetry metrics (`oban.job.stop.duration`, `oban.job.stop.count`) with top-level `:worker` tags. However, Oban nests the worker name inside the `metadata.job` struct (`metadata.job.worker`), causing Phoenix LiveDashboard to drop the metrics.
* **The Fix:** Implemented a dedicated `extract_oban_tags/1` tag transformation function in `FlyrankCapstoneSocialStudioWeb.Telemetry` using `:tag_values`.

---

## 4. Key Architectural Decisions & Changes Made

1. **Strict Review Gate:** Refusing to allow any unapproved variant to be scheduled at both the database schema level (`Slot.changeset/2`) and API controller boundary (`Publishing.schedule_variant/2`).
2. **Partial Unique PostgreSQL Index for Idempotency:** Implemented a partial unique index on `publish_attempts (slot_id) WHERE status = 'success'` to guarantee that no slot can ever be dispatched more than once under concurrent workers or network retries.
3. **Pluggable Adapter Seam:** Built `SocialPublisher` behaviour with zero business logic dependencies on whether a platform is real (Telegram) or a local simulation (Mock X, Mock LinkedIn).
4. **Resumable Workers:** Oban-backed durable scheduling where worker crashes mid-batch resume safely without duplicate posts.

---

## 5. Build & Setup History: Scalar, Docker & Database

*(Reference log of infrastructure setup and Docker PostgreSQL volume reconciliation)*

### Problem
The Scalar API reference page loaded at `/api/scalar`, but it could not load the OpenAPI document from `/api/openapi.json`. The browser reported a 500 response from the document endpoint:
```text
Failed to load resource: the server responded with a status of 500
Missing private.open_api_spex key in conn
```

### Root Causes
1. **OpenAPI plug missing from doc routes:** Added `:docs` pipeline running `OpenApiSpex.Plug.PutApiSpec`.
2. **OpenAPI routes had no operation metadata:** Added operation specs to all controllers.
3. **PostgreSQL volume version alignment:** Reconciled Docker Compose image with `postgres:16-alpine` to maintain volume consistency.

---

## 6. Personal Reflections & Learnings

*(Feel free to personalize this section with your own reflections before final submission!)*

* What surprised you most about building with Elixir / OTP?
* How did the adapter architecture make it easier to add new platforms?
* What was your biggest takeaway from implementing real database-level idempotency?
