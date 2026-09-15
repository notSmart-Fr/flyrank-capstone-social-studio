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

#### Verified Invariant Behaviors:

1. `ingest_and_generate/2` creates a post and two draft variants for the requested `telegram` and `mock_x` platforms.
2. `mock_x` content exceeding the 280-character limit and two-hashtag limit is rejected with explicit changeset errors naming both violated rules.
