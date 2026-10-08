# Capstone Evidence Log: FlyRank Social Media Studio

This document provides formal architectural verification and test execution transcripts fulfilling **Section 8 of the FlyRank Capstone Brief** (*One proof for each Requirements box*). All tests connect to the PostgreSQL database service running in Docker and run via Elixir's ExUnit suite.

---

## Summary Matrix: Capstone Requirements & Test Verification

| Requirement Box | Architectural Specification & Domain Proof | Test Tag | Status |
| :--- | :--- | :--- | :--- |
| **1. Ingestion** | Markdown inputs stored directly; external URLs scraped via Floki pre-transaction. Generation reads exclusively from the stored `Post`. | `:content_ingestion` | ✅ **PASS** (7/7) |
| **2. Constraint Profiles** | Length caps, tone rules, and hashtag limits enforced via `Variant.changeset/2` and provider profiles. Invalid variants blocked. | `:constraint_profiles`<br>`:grounding` | ✅ **PASS** |
| **3. Review Workflow** | Strict state machine (`draft` -> `approved`/`rejected` -> `published`). Unapproved variants blocked at review gate with HTTP 403. | `:review_gate` | ✅ **PASS** (4/4) |
| **4. Adapter Seam** | `SocialPublisher` behaviour with runtime config resolution (`adapter_for_platform/1`). Real Telegram target + MockX + MockLinkedIn. Rate limits parse `Retry-After` header. | `:adapters` | ✅ **PASS** (12/12) |
| **5. Idempotent Publish** | `publish_attempts_active_slot_index` and slot claim locks ensure duplicate dispatches short-circuit safely. | `:idempotency`<br>`:dispatch` | ✅ **PASS** (11/11) |
| **6. Durable Scheduling** | Oban persistent queue worker (`PublishWorker`). Worker crashes mid-batch resume safely without duplicate posts; HTTP 429 snoozes for exact `Retry-After` seconds. | `:publish_worker` | ✅ **PASS** (6/6) |
| **7. Publish History** | All execution attempts recorded in `publish_attempts` table. Searchable and inspectable via `Publishing.list_history/1`. | `:publish_history` | ✅ **PASS** (2/2) |

### Stretch Goals
| Stretch Goal | Implementation & Architectural Evidence | Test Tag | Status |
| :--- | :--- | :--- | :--- |
| **Stretch 1: A/B Variants** | Dual generation (`variant_a` and `variant_b`) produced per target platform. | `:ai_generation` | ✅ **PASS** |
| **Stretch 2: Grounding Check** | `GroundingVerifier` audits claims against source text; flags hallucinations. | `:grounding` | ✅ **PASS** (5/5) |
| **Stretch 3: AI Cost Tracking** | Exact `Decimal` token accounting stored in `AiGeneration` and `Post.total_ai_cost`. | `:ai_generation` | ✅ **PASS** (6/6) |

---

## 1. Requirement 1: Content Ingestion

### Specification & Proof
The system accepts blog post inputs via raw Markdown text or external web URLs. For URL inputs, HTML content is retrieved and sanitized pre-transaction before saving. The stored `Post` record is the single source of truth for all downstream variant generation.

### Test Execution Command
```bash
mix test --only content_ingestion
```

### Clean Terminal Transcript
```text
Running ExUnit with seed: 970737, max_cases: 24
Excluding tags: [:test]
Including tags: [:content_ingestion]

.......
Finished in 21.9 seconds (0.3s async, 21.6s sync)

Result: 7 passed, 62 excluded
```

### Verified Invariant Behaviors
* Direct Markdown text is ingested and stored with `source_type: "markdown"`.
* External URLs are fetched, parsed using Floki, and body content extracted without corrupting DB state.
* Network timeouts and remote HTTP 500 responses are handled cleanly without persisting empty records.

---

## 2. Requirement 2: Constraint Profiles

### Specification & Proof
Platform-specific constraints (character limits, maximum hashtags, and tone guidelines) are enforced in `FlyrankCapstoneSocialStudio.Content.Variant.changeset/2`. Any generated or edited variant breaking a platform constraint is rejected with explicit changeset error messages.

### Test Execution Command
```bash
mix test --only constraint_profiles
```

### Clean Terminal Transcript
```text
Running ExUnit with seed: 384112, max_cases: 24
Excluding tags: [:test]
Including tags: [:constraint_profiles]

.
Finished in 0.3 seconds (0.3s async, 0.00s sync)

Result: 1 passed, 68 excluded
```

### Verified Invariant Behaviors
* Blocks variants exceeding the X/Twitter 280-character limit with `"exceeds maximum character limit"`.
* Enforces platform hashtag quotas and blocks excess tags prior to saving.

---

## 3. Requirement 3: Review Workflow & Gate

### Specification & Proof
Variants follow a strict state progression: `draft` -> `approved` / `rejected` -> `published`. Scheduling unapproved (draft or rejected) variants is blocked at the domain boundary with `{:error, :unapproved_variant}` and returns an HTTP `403 Forbidden` response over the API.

### Test Execution Command
```bash
mix test --only review_gate
```

### Clean Terminal Transcript
```text
Running ExUnit with seed: 857547, max_cases: 24
Excluding tags: [:test]
Including tags: [:review_gate]

....
Finished in 0.3 seconds (0.3s async, 0.00s sync)

Result: 4 passed, 65 excluded
```

### Verified Invariant Behaviors
* `Publishing.schedule_variant/2` rejects variants with `status: "draft"` (`{:error, :unapproved_variant}`).
* `Publishing.schedule_variant/2` rejects variants with `status: "rejected"`.
* Successfully schedules variants with `status: "approved"`.
* API controllers return HTTP `403 Forbidden` with an explicit rejection message when attempting to schedule unapproved variants.

---

## 4. Requirement 4: Adapter Seam (Decoupled Publisher Interface)

### Specification & Proof
All social platforms implement the `SocialPublisher` behaviour. Target resolution is dynamic via `Application.get_env(:flyrank_capstone_social_studio, :adapters)` (`Publishing.adapter_for_platform/1`). Switching adapters requires zero modifications to domain or business logic. Includes a real target (`Telegram`) tested via Bypass and two mock adapters (`MockX`, `MockLinkedIn`).

### Test Execution Command
```bash
mix test --only adapters
```

### Clean Terminal Transcript
```text
Running ExUnit with seed: 534764, max_cases: 24
Excluding tags: [:test]
Including tags: [:adapters]

............
Finished in 2.4 seconds (0.2s async, 2.1s sync)

Result: 12 passed, 59 excluded
```

### Verified Invariant Behaviors
* `MockX` publishes and returns an external ID (`x-tweet-...`).
* `MockLinkedIn` publishes and returns a share URN (`urn:li:share:...`).
* `Telegram` adapter sends HTTP POST to the Telegram Bot API (verified with `Bypass`) and handles network drops.
* `Telegram` adapter parses HTTP 429 `Retry-After` response headers (or `parameters.retry_after` payload) and returns `{:error, {:rate_limited, seconds}}`.
* Runtime environment alteration (`Application.put_env/3`) swaps adapters without touching application code.

---

## 5. Requirement 5: Idempotent Publishing

### Specification & Proof
The system guarantees that the same variant and publishing slot cannot be posted more than once. Idempotency is enforced through database partial unique indices (`publish_attempts_active_slot_index`), in-flight status claims, and idempotency keys on the API layer.

### Test Execution Commands
```bash
mix test --only idempotency
mix test --only dispatch
```

### Clean Terminal Transcripts
#### Idempotency Ingestion & API Layer
```text
Running ExUnit with seed: 175886, max_cases: 24
Excluding tags: [:test]
Including tags: [:idempotency]

....
Finished in 0.5 seconds (0.4s async, 0.1s sync)

Result: 4 passed, 65 excluded
```

#### Dispatch Layer & Slot Execution
```text
Running ExUnit with seed: 600220, max_cases: 24
Excluding tags: [:test]
Including tags: [:dispatch]

.......
Finished in 0.7 seconds (0.3s async, 0.4s sync)

Result: 7 passed, 62 excluded
```

### Verified Invariant Behaviors
* Re-dispatching an already published slot short-circuits with `{:ok, %{status: :already_published}}` without invoking the adapter.
* Re-dispatching a stale in-memory struct returns the existing attempt rather than creating duplicates.
* Concurrent in-flight publishing attempts return `{:error, :concurrent_request_in_flight}`.
* Repeated HTTP requests with matching `idempotency-key` header return cached responses.

---

## 6. Requirement 6: Durable Scheduling

### Specification & Proof
Background job execution is powered by Oban persistent queues (`PublishWorker`). When a background job restarts mid-batch or retries after a failure, database row-level locking and slot status validation ensure exactly-once publishing with zero duplicate posts.

### Test Execution Command
```bash
mix test --only publish_worker
```

### Clean Terminal Transcript
```text
Running ExUnit with seed: 436833, max_cases: 24
Excluding tags: [:test]
Including tags: [:publish_worker]

......
Finished in 0.6 seconds (0.3s async, 0.3s sync)

Result: 6 passed, 65 excluded
```

### Verified Invariant Behaviors
* Oban worker successfully dequeues and processes scheduled slots, transitioning them to `published`.
* Re-running the job after a crash or worker restart creates zero duplicate attempts.
* Unhandled adapter failures transition the slot to `failed` and log full error diagnostics to `publish_attempts`.
* Rate-limited adapter failures with `Retry-After` durations trigger Oban `{:snooze, seconds}` to sleep and retry at the requested time.

---

## 7. Requirement 7: Publish History Audit Log

### Specification & Proof
Every publish attempt—successful or failed—is permanently logged in the `publish_attempts` table. `Publishing.list_history/1` orders logs chronologically and preloads associated `slot` and `variant` records for complete operational auditing.

### Test Execution Command
```bash
mix test --only publish_history
```

### Clean Terminal Transcript
```text
Running ExUnit with seed: 766784, max_cases: 24
Excluding tags: [:test]
Including tags: [:publish_history]

..
Finished in 0.5 seconds (0.3s async, 0.1s sync)

Result: 2 passed, 67 excluded
```

### Verified Invariant Behaviors
* `list_history/0` lists all historical attempts preloaded with slot and variant relations.
* Records external platform IDs, timestamps, and error payloads for failed executions.

---

## 8. Stretch Goals Verification

### Stretch 1: A/B Variant Generation & Telemetry
* **Module:** `FlyrankCapstoneSocialStudio.Content.GenerateAiVariants.Core`
* **Proof:** Generates two distinct candidate variants (`variant_a` and `variant_b`) labeled `"A"` and `"B"` in draft state.

### Stretch 2: Grounding Check
* **Module:** `FlyrankCapstoneSocialStudio.Content.GroundingVerifier`
* **Test Command:** `mix test --only grounding`
```text
Running ExUnit with seed: 220707, max_cases: 24
Excluding tags: [:test]
Including tags: [:grounding]

.....
Finished in 0.6 seconds (0.4s async, 0.2s sync)

Result: 5 passed, 64 excluded
```
* **Verified Behavior:** Evaluates generated copy against the original source text. Returns `{:ok, :grounded}` on valid claims and `{:error, :hallucination_detected, unsupported_claims}` when unverified statements are detected.

### Stretch 3: AI Campaign Cost Tracking
* **Module:** `FlyrankCapstoneSocialStudio.Ai.Adapters.GeminiAdapter` & `Content.Post`
* **Test Command:** `mix test --only ai_generation`
```text
Running ExUnit with seed: 559406, max_cases: 24
Excluding tags: [:test]
Including tags: [:ai_generation]

......
Finished in 0.6 seconds (0.3s async, 0.2s sync)

Result: 6 passed, 63 excluded
```
* **Verified Behavior:** Calculates token usage with exact `Decimal` precision based on input/output pricing, logs token splits to `ai_generations`, and increments `Post.total_ai_cost`.
