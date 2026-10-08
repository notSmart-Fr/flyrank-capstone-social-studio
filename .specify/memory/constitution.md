<!--
Sync Impact Report:
- Version Change: Unversioned -> 1.0.0 (Initial Ratification)
- Modified Principles: Initialized Core Principles 1-5 from FlyRank architecture specifications
- Added Sections:
  - Architecture & Technology Standards
  - Quality Gates & Verification Workflow
  - Governance & Operational Policies
- Removed Sections: None (initial scaffold replacement)
- Follow-up TODOs: None
-->

# FlyRank Social Media Studio Constitution

## Core Principles

### I. Single Source of Truth & Content Ingestion Integrity
Content enters the system strictly as raw Markdown or an external web URL. For URL inputs, content is fetched and sanitized pre-transaction. The resulting record is stored as the immutable single source of truth (`posts` table), and all downstream variant generation reads exclusively from this stored record.

### II. Code-Enforced Constraint Profiles & Factual Grounding
Platform constraints (character limits, maximum hashtags, and tone guidelines) are enforced deterministically in core domain logic (`Variant.changeset/2`). Generated variants that break platform rules or fail factual grounding audits against source content are blocked at the domain boundary before entering the review pipeline.

### III. Uncompromising Review Gate (Human-in-the-Loop)
Every content variant adheres to an explicit state machine: `draft` -> `approved` / `rejected` -> `published`. Scheduling unapproved variants is strictly prohibited by domain business logic and returns an HTTP `403 Forbidden` error (`{:error, :unapproved_variant}`) before any database slot or background job can be scheduled.

### IV. Decoupled Adapter Seam & Zero-Code Swaps
All social platforms implement the `SocialPublisher` behaviour. Target resolution is dynamic via runtime configuration (`Publishing.adapter_for_platform/1`). Switching or swapping target adapters—including mock adapters (`MockX`, `MockLinkedIn`) and real platforms (`Telegram`)—requires zero alterations to core business logic.

### V. Idempotent Dispatch & Resilient Scheduling
The system guarantees exactly-once publication under retries, worker crashes, or concurrent executions via database unique indices (`publish_attempts_active_slot_index`), row-level locks, and Oban persistent background queues. Rate-limited requests (HTTP 429) dynamically respect `Retry-After` headers via worker snoozing, and every execution attempt is permanently recorded in `publish_attempts` for complete auditability.

## Architecture & Technology Standards

- **Runtime & Framework**: Elixir 1.20+ and Phoenix 1.8+ running on the Erlang OTP/BEAM platform.
- **Persistence & Background Jobs**: PostgreSQL with Ecto for relational integrity; Oban for durable background worker queues.
- **HTTP Client**: Use `:req` (`Req`) exclusively for all external HTTP communications; third-party alternatives (`:httpoison`, `:tesla`) are forbidden.
- **Frontend & Real-Time**: Phoenix LiveView with Tailwind CSS v4; collections managed via LiveView streams to ensure bounded memory usage.
- **Telemetry & Cost Tracking**: Financial token accounting computed with exact `Decimal` precision and logged per post.

## Quality Gates & Verification Workflow

- **Test-Driven Invariants**: All domain state transitions, constraint profile validations, review gates, and adapter seams must have corresponding ExUnit test coverage.
- **Precommit Enforcement**: The `mix precommit` suite (formatting, compilation warnings, and automated test execution) must pass with zero failures before changes are committed.
- **Evidence Audit Trail**: Verification transcripts and invariant proofs must be maintained in `EVIDENCE.md` mapped to project requirements.

## Governance

- This constitution supersedes ad-hoc development practices and design compromises.
- Any change to core principles requires an explicit amendment, version bump, and architectural justification.
- Complexity additions must be defended against simpler alternatives.

**Version**: 1.0.0 | **Ratified**: 2026-10-08 | **Last Amended**: 2026-10-08
