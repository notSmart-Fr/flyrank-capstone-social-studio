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
