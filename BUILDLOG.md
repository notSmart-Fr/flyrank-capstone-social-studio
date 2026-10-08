# BUILDLOG.md: AI Pairing & Engineering Decisions

This document details where AI assistants provided velocity, where AI suggestions were flawed or architecturally incorrect, and how domain decisions were resolved.

---

## 1. Stack & Runtime Strategy

* **AI Contribution:** Recommended Elixir and the BEAM ecosystem over Node.js and Python for building a resilient publishing engine. Highlighted lightweight concurrency, actor isolation, and battle-tested fault tolerance.
* **Outcome:** The BEAM model was well-suited for stateful publishing pipelines, process supervision, and native telemetry.

---

## 2. Ingestion & Floki Parsing

* **Where AI Helped:** Accelerated initial HTML boilerplate parsing using `Floki` to extract article body text.
* **Where AI Failed (Happy-Path Assumption):** 
  * The initial AI-generated scraper lacked network retry handling and defensive HTTP status validation.
  * Ingestion was initially treated as a synchronous, blocking request, failing to account for flaky remote hosts, hanging TCP connections, and upstream 500 errors.
* **What I Changed:** Hardened the ingestion pipeline with explicit timeout guards and pre-transaction sanitization so external connection failures do not corrupt database state.

---

## 3. Idempotency & Delivery Guarantees

* **Where AI Failed (Incorrect Domain Solution):**
  * **Failure 1 (Missing Network Semantics):** AI initially omitted network-level idempotency, relying on basic client calls without deduping headers.
  * **Failure 2 (Content Hashing Misconception):** When prompted for idempotency, AI suggested deduplication via hashing the post body (`content_hash`). This confused domain uniqueness with delivery idempotency—a marketing team intentionally publishing identical text to different slots or campaigns should not be blocked.
* **What I Changed:** Rejected body-content hashing for delivery control. Implemented true network and database-level idempotency:
  * Supported `Idempotency-Key` headers on incoming dispatch requests.
  * Enforced slot-level idempotency via a PostgreSQL partial unique index (`publish_attempts_active_slot_index`) and explicit transactional slot-claiming locks (`SELECT FOR UPDATE`).

---

## 4. Asynchronous Workflow & Real-Time Feedback

* **Where AI Failed (Missing Lifecycle & Blocking UI):**
  * **Failure 1 (Un-instrumented Generation):** AI generated variants and called external LLM endpoints synchronously inside LiveView process loops without progress feedback, causing UI freezes and dropped socket connections.
  * **Failure 2 (Hardcoded Grounding Mocks):** In early LiveView prototypes, AI hardcoded grounding validation directly into the view layer rather than running it through an asynchronous domain contract. This caused generated variants to trigger constraint violations during review with no valid path to transition their status.
* **What I Changed:** Refactored variant generation and grounding verification into dedicated asynchronous workers (`VerifyGroundingWorker`). Added real-time LiveView event streaming with clear UI loading indicators.

---

## 5. Rate Limits & Background Queueing

* **Where AI Failed (Ignore Rate-Limit Metadata):**
  * When implementing external platform publishing, AI handled failed HTTP requests with basic exponential backoff, ignoring upstream HTTP 429 `Retry-After` headers.
* **What I Changed:** Extracted the `Retry-After` header directly inside the adapter layer, returning `{:error, {:rate_limited, seconds}}`. Wired this into Oban’s native `{:snooze, seconds}` callback so the queue sleeps for the exact time requested by the target API without exhausting attempt limits.

---

## 6. Spec Gap Analysis: Pre-Publish Validation

* **Observation:** The brief specifies enforcing constraint profiles strictly during variant generation before human review.
* **Identified Gap:** The pipeline did not re-evaluate constraints at publish time. If upstream character rules change or dynamic text (such as UTM parameters or tracking links) is appended at dispatch, an invalid post could reach the network.
* **Mitigation:** Implemented secondary defense-in-depth constraint checks directly inside the adapter seam prior to payload dispatch.
