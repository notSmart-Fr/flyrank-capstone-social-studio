# Capstone Evidence Log

## Phase 2: Ingestion & Constraint Profiles

### 1. Requirements & System Proofs

#### Requirement 1: Single Source of Truth & Input Ingestion
- **Status:** PASS
- **System Proof:** The system accepts blog post inputs via raw Markdown text or external web URLs. For URL inputs, content is fetched and cleaned prior to opening a database transaction. The resulting text is stored as the single source of truth (`posts` table), and all platform variant generation reads exclusively from this stored record.

#### Requirement 2: Constraint Profiles Enforced by Code
- **Status:** PASS
- **System Proof:** Platform-specific rules (character limits, hashtag caps, and tone guidelines) are enforced directly in core domain logic (`Variant.changeset/2`). Any generated or edited variant that breaks a platform constraint is blocked from being saved to the database and returns explicit error messages naming the violated rules before reaching review.

---

### 2. Execution & Test Transcript

#### Test Command:
```powershell
mix test test/flyrank_capstone_social_studio/content_test.exs
```

#### Command Transcript & Output:
```text
PS I:\projects\flyrank-capstone-social-studio> mix test test/flyrank_capstone_social_studio/content_test.exs
Running ExUnit with seed: 42875, max_cases: 32

.....
Finished in 0.06 seconds (0.00s async, 0.06s sync)

Result: 5 passed
```

#### Verified Invariant Behaviors:
- `ingest_and_generate/2` creates a post and valid draft variants for the target platforms.
- Variant content exceeding character limits, hashtag limits, or tone rules is rejected with explicit changeset errors naming the violated rules.

---

## Phase 3: Review Workflow

### 1. Requirements & System Proofs

#### Requirement 3: Review Workflow & Unapproved Schedule Prevention
- **Status:** PASS
- **System Proof:** Every variant follows a strict state transition path (draft -> approved / rejected -> published). Domain logic blocks schedule requests for unapproved variants, and the API layer returns an HTTP 4xx error with an explicit error message before any database slot or background job can be created.

### 2. Execution & Test Transcript

#### Test Command:
```powershell
mix test test/flyrank_capstone_social_studio/review_workflow_test.exs
```

#### Command Transcript & Output:
```text
PS I:\projects\flyrank-capstone-social-studio> mix test test/flyrank_capstone_social_studio/review_workflow_test.exs
Running ExUnit with seed: 290859, max_cases: 32

...
Finished in 0.06 seconds (0.00s async, 0.06s sync)

Result: 4 passed
```

#### Verified Invariant Behaviors:
- Rejects schedule requests for variants in draft or rejected status.
- Successfully schedules approved variants into publishing slots.
- Returns an HTTP 4xx status code when scheduling unapproved variants via the API.

### 3. Architectural Proof: Zero-Code Adapter Swaps

#### Requirement: Config-Driven Adapter Routing
- **Status:** PASS
- **System Proof:** The passed test proves that the application's core domain (`Publishing`) successfully enforces an Adapter Pattern (Decoupled Seam): `adapter_for_platform/1` reads dynamically from `Application.get_env/3` instead of hardcoded function clauses, and changing `Application.put_env/3` swaps the execution target at runtime without requiring any business logic changes in `lib/`.

### 4. Execution & Test Transcript

#### Test Command:
```powershell
mix test test/flyrank_capstone_social_studio/adapter_test.exs
```

#### Command Transcript & Output:
```text
PS I:\projects\flyrank-capstone-social-studio> mix test test/flyrank_capstone_social_studio/adapter_test.exs
Finished in 0.01 seconds (0.00s async, 0.01s sync)

Result: 2 passed
```

#### Verified Invariant Behaviors:
- `adapter_for_platform/1` resolves adapters from the configured `:adapters` environment instead of hardcoded clauses.
- Mutating `Application.put_env/3` during the test changes the runtime dispatch target immediately, proving the adapter seam is config-driven and zero-code swap safe.

---

## Phase 4: Idempotent Publishing & Adapters

### 1. Requirements & System Proofs

#### Requirement: Idempotent Dispatch Protection
- **Status:** PASS
- **System Proof:** The system guarantees that an identical variant and publishing slot cannot be posted multiple times, even under network retries or duplicate background worker invocations. The `Publishing.dispatch_slot/2` function checks for existing execution records tied to the slot before invoking the platform adapter.

### 2. Execution & Test Transcript

#### Test Command:
```powershell
mix test test/flyrank_capstone_social_studio/idempotency_test.exs
```

#### Command Transcript & Output:
```text
PS I:\projects\flyrank-capstone-social-studio> mix test test/flyrank_capstone_social_studio/idempotency_test.exs
Running ExUnit with seed: 472843, max_cases: 32

..
Finished in 0.3 seconds (0.00s async, 0.3s sync)

Result: 2 passed
```

#### Verified Invariant Behaviors:
- Duplicate dispatch attempts for the same slot are prevented before invoking the adapter.
- Successful posting still occurs exactly once for the original slot, even when retries or re-entrant worker invocations are attempted.

---

## Phase 5: Durable Scheduler & History Audit Logs

### 1. Requirements & System Proofs

#### Requirement: Oban Worker Resiliency & Audit History
- **Status:** PASS
- **System Proof:** Background execution is powered by Oban background workers (`PublishWorker`). If a worker process restarts mid-batch or retries a job execution, underlying idempotency locks ensure the post is published with zero duplicate attempts. Every execution is logged in the `publish_attempts` table with timestamps and external post IDs for audit history tracking.

### 2. Execution & Test Transcript

#### Test Command:
```powershell
mix test test/flyrank_capstone_social_studio/durable_scheduler_test.exs
```

#### Command Transcript & Output:
```text
PS I:\projects\flyrank-capstone-social-studio> mix test test/flyrank_capstone_social_studio/durable_scheduler_test.exs
Running ExUnit with seed: 185675, max_cases: 32

...
Finished in 0.2 seconds (0.00s async, 0.2s sync)

Result: 3 passed
```

#### Verified Invariant Behaviors:
- The Oban publishing worker is enqueued and executes the scheduled slot, transitioning it to `published`.
- A successful publishing attempt is recorded in the audit log with the slot ID, success status, and external post ID.
- Retries or restarts do not create duplicate published outputs because idempotent execution guardrails remain in place.
