# Capstone Evidence Log

## Phase 2: Ingestion & Constraint Profiles

### Requirement: Constraint Profiles Enforced by Code
- **Status:** PASS
- **Proof:** Run `mix test test/flyrank_capstone_social_studio/content_test.exs`

#### Command Transcript & Output:
```powershell
PS I:\projects\flyrank-capstone-social-studio> mix test test/flyrank_capstone_social_studio/content_test.exs
Running ExUnit with seed: 277494, max_cases: 32

..
Finished in 0.05 seconds (0.00s async, 0.05s sync)

Result: 2 passed
```

## Phase 5: Durable Scheduler & History Audit Logs

### Requirement: Oban Background Execution & History Logging
- **Status:** PASS
- **Proof:** Run `mix test test/flyrank_capstone_social_studio/durable_scheduler_test.exs`

#### Command Transcript & Output:
```powershell
PS I:\projects\flyrank-capstone-social-studio> mix test test/flyrank_capstone_social_studio/durable_scheduler_test.exs
Running ExUnit with seed: 710293, max_cases: 32

..
Finished in 0.08 seconds (0.02s async, 0.06s sync)

Result: 2 passed
```

#### Verified Invariant Behaviors:

1. The Oban publishing worker is enqueued and executes the scheduled slot, transitioning it to `published`.
2. A successful publishing attempt is recorded in the history audit log with the slot ID, success status, and external post ID.

#### Verified Invariant Behaviors:

1. `ingest_and_generate/2` creates a post and two draft variants for the requested `telegram` and `mock_x` platforms.
2. `mock_x` content exceeding the 280-character limit and two-hashtag limit is rejected with explicit changeset errors naming both violated rules.

## Phase 3: Review Workflow

### Requirement: Review Workflow & Unapproved Schedule Prevention
- **Status:** PASS
- **Proof:** Run `mix test test/flyrank_capstone_social_studio/review_workflow_test.exs`

#### Command Transcript & Output:
```powershell
PS I:\projects\flyrank-capstone-social-studio> mix test test/flyrank_capstone_social_studio/review_workflow_test.exs
Compiling 1 file (.ex)
warning: Failed to symlink node_modules folder for colocated assets: :eperm

Running ExUnit with seed: 290859, max_cases: 32

...
Finished in 0.06 seconds (0.00s async, 0.06s sync)

Result: 3 passed
```

## Phase 4: Adapters & Idempotency

### Requirement: Idempotent Dispatcher Protection
- **Status:** PASS
- **Proof:** Run `mix test test/flyrank_capstone_social_studio/idempotency_test.exs`

#### Command Transcript & Output:
```powershell
PS I:\projects\flyrank-capstone-social-studio> mix test test/flyrank_capstone_social_studio/idempotency_test.exs
Running ExUnit with seed: 250904, max_cases: 32

..
Finished in 0.1 seconds (0.00s async, 0.1s sync)

Result: 2 passed
```
