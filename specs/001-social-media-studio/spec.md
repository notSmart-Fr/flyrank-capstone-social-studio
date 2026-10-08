# Feature Specification: Social Media Studio Campaign Management

**Feature Branch**: `001-social-media-studio`

**Created**: 2026-10-08

**Status**: Complete / Validated

**Input**: User description: "Create specification based on implemented Social Media Studio system in EVIDENCE.md and Capstone Brief, covering core requirements and stretch goals with frozen scope."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Multi-Channel Campaign Ingestion & Generation (Priority: P1)

As a content marketer, I want to submit a blog post (via direct text or web URL) and have the system automatically create tailored social media post variants that adhere strictly to platform constraints, so that I can repurpose long-form articles into social posts without manual copy-pasting or rule checking.

**Why this priority**: Ingestion and constraint-compliant generation form the essential foundation of the entire system. Without stored source content and compliant variants, no review or publishing can occur.

**Independent Test**: Can be tested by providing a blog post in Markdown format or submitting a live URL. The system stores the post as the immutable source of truth and produces draft variants for target platforms (e.g., Telegram, X, LinkedIn) that pass length, hashtag, and tone checks.

**Acceptance Scenarios**:
1. **Given** a valid blog post URL, **When** the user submits the URL for ingestion, **Then** the system extracts the clean body text, stores it, and generates platform variants in `draft` status.
2. **Given** raw Markdown text, **When** the user submits the text, **Then** the system creates a source post record without external network calls and generates compliant draft variants.
3. **Given** a generated or edited variant that exceeds a platform's character limit or hashtag quota, **When** validation executes, **Then** the system blocks the variant and flags explicit validation errors naming the broken rules before review.

---

### User Story 2 - Human-in-the-Loop Review Gate (Priority: P2)

As an editor or marketing manager, I want to review, edit, approve, or reject draft variants before anything is allowed to be scheduled, so that unapproved, off-brand, or unverified content is never published.

**Why this priority**: Guardrails against accidental or unauthorized publishing are non-negotiable for business credibility and safety.

**Independent Test**: Can be tested by attempting to schedule variants in `draft` or `rejected` status. The system rejects the action with a 4xx client error, while allowing `approved` variants to be scheduled into calendar slots.

**Acceptance Scenarios**:
1. **Given** a variant with `draft` or `rejected` status, **When** an attempt is made to schedule a publishing slot, **Then** the system refuses the request with an HTTP 4xx status and an explicit rejection message.
2. **Given** an approved variant, **When** a user schedules it for a specific timestamp, **Then** the system reserves a publishing slot and sets its status to `pending`.
3. **Given** a rejected variant, **When** the editor enters rejection feedback, **Then** the variant status is updated to `rejected` with the reason recorded.

---

### User Story 3 - Idempotent Multi-Platform Publishing (Priority: P3)

As a social media manager, I want scheduled posts to be published through an extensible adapter layer that guarantees exactly-once delivery, so that network retries or worker restarts never post duplicate messages to audience feeds.

**Why this priority**: Idempotency and resilient delivery are the core technical requirements that differentiate an enterprise-grade publishing system from basic scripts.

**Independent Test**: Can be tested by executing duplicate dispatch attempts for the same scheduled slot or abruptly stopping and restarting a background worker mid-batch; the external platform receives exactly one post, and duplicate calls return cached success without second API calls.

**Acceptance Scenarios**:
1. **Given** an approved and scheduled slot, **When** the publishing time arrives, **Then** the system delivers the variant to the designated platform adapter and transitions the slot to `published`.
2. **Given** a slot that has already been published, **When** a duplicate dispatch or network retry occurs, **Then** the system detects the existing execution, creates zero new posts, and returns the previous successful result.
3. **Given** an external platform returns a rate-limit error (HTTP 429) with a retry duration, **When** the dispatcher handles the response, **Then** the system defers execution for the requested duration without failing the slot permanently.

---

### User Story 4 - Audit Trail & Delivery History (Priority: P4)

As an operations lead or auditor, I want a comprehensive log of every publishing attempt—including timestamp, platform target, external post identifiers, and error diagnostics—so that I can monitor campaign health and troubleshoot failures.

**Why this priority**: Visibility and auditability are required to inspect real-world publishing outcomes and verify platform responses.

**Independent Test**: Can be tested by querying the publish history view after running successful and simulated failing dispatches; each attempt is recorded chronologically with full status and metadata.

**Acceptance Scenarios**:
1. **Given** a completed publishing dispatch, **When** viewing the publishing history, **Then** the record displays the timestamp, target platform, external post ID, and status (`success` or `failure`).
2. **Given** an adapter failure (e.g., credentials missing or service unavailable), **When** inspected in the history log, **Then** the failure record displays the specific error payload and diagnostic message.

---

### User Story 5 - A/B Candidate Generation, Grounding & AI Cost Telemetry (Priority: P5 - Stretch)

As a growth marketer using AI-assisted copywriting, I want to receive dual candidate variants (Variant A and Variant B), have claims audited against the source text to prevent hallucinations, and see the exact financial cost of generation, so that I can choose top-performing copy while monitoring AI expenditure.

**Why this priority**: High-value stretch capabilities that elevate content quality, safeguard factual accuracy, and provide financial transparency.

**Independent Test**: Can be tested by generating variants with AI enabled; the system returns A/B candidate pairs, verifies factual consistency against source text, and attaches calculated monetary cost to the campaign record.

**Acceptance Scenarios**:
1. **Given** a source post, **When** AI variant generation runs, **Then** the system outputs two distinct candidate drafts labeled "Variant A" and "Variant B".
2. **Given** a candidate variant containing unverified facts not present in the source article, **When** the grounding audit executes, **Then** the claim is flagged as ungrounded and blocked from automatic approval.
3. **Given** AI tokens consumed during generation, **When** generation completes, **Then** the exact monetary cost is computed with precision arithmetic and aggregated on the source post record.

---

### Edge Cases

- **Scraper Failure / Unreachable URL**: Remote HTTP 500 errors or network connection timeouts during URL ingestion must not persist half-initialized database records.
- **Concurrent In-Flight Duplicate Dispatches**: Simultaneous double-clicks or parallel processes attempting to dispatch the same slot at the exact same millisecond must trigger an in-flight mutual exclusion lock (`concurrent_request_in_flight`).
- **External Platform Rate Limiting (HTTP 429)**: When an external API issues a rate-limit response with a `Retry-After` header, the system must snooze the background task until the specified time rather than marking the slot as permanently dead.
- **Worker Crash Mid-Batch**: When a background scheduler process terminates unexpectedly while processing a batch, subsequent recovery must resume cleanly with zero duplicate publications.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST accept long-form content via direct Markdown text or external web URL.
- **FR-002**: For URL inputs, system MUST fetch, sanitize, and extract article body content before opening a database transaction.
- **FR-003**: System MUST store the ingested content as a single source of truth (`Post`), and all subsequent generation MUST read strictly from this stored copy.
- **FR-004**: System MUST define and enforce platform constraint profiles (character length caps, maximum hashtags, tone guidelines) in domain validation rules.
- **FR-005**: System MUST block any variant that violates a constraint profile from reaching review, returning explicit error messages naming the broken rules.
- **FR-006**: System MUST enforce a strict review lifecycle: `draft` -> `approved` / `rejected` -> `published`.
- **FR-007**: System MUST refuse scheduling requests for any variant in `draft` or `rejected` status, returning an HTTP 4xx error with an explanatory message.
- **FR-008**: System MUST provide a decoupled publisher interface (`SocialPublisher`) supporting at least one real free delivery target (Telegram) and two mock targets (MockX, MockLinkedIn).
- **FR-009**: System MUST resolve publishing adapters dynamically from configuration so that changing delivery targets touches zero business logic.
- **FR-010**: System MUST guarantee idempotent publication such that the same variant and scheduled slot cannot be published more than once, even under retries.
- **FR-011**: System MUST utilize durable background scheduling that continues without duplicate posts following worker process restarts.
- **FR-012**: System MUST parse rate-limit `Retry-After` headers on HTTP 429 responses and snooze background retries for the requested duration.
- **FR-013**: System MUST record every publish attempt (success, failure, rate limit) in a searchable audit history log with external IDs and error diagnostics.
- **FR-014**: System MUST support generating dual A/B candidate variants per target platform.
- **FR-015**: System MUST verify factual grounding of generated variants against source text and flag unsupported claims.
- **FR-016**: System MUST track AI token consumption and calculate exact monetary cost per campaign.
- **FR-017**: System MUST maintain clean secret management, loading API tokens strictly from environment variables without committing credentials.

---

### Key Entities

- **Post (Source of Truth)**: Represents the ingested blog article. Key attributes include title, body content, source type (`markdown` or `url`), source URL, and cumulative AI cost.
- **Variant**: Represents a platform-specific social adaptation. Key attributes include platform name, content body, variant label (`A` or `B`), status (`draft`, `approved`, `rejected`, `published`), character count, and hashtag count.
- **Publishing Slot**: Represents a reserved time window for publication. Key attributes include scheduled timestamp, slot status (`pending`, `published`, `failed`), and unique idempotency key.
- **Publish Attempt (Audit Record)**: Represents an immutable dispatch execution record. Key attributes include timestamp, target adapter name, outcome status (`pending`, `success`, `failure`), external post identifier, and raw response/error payload.
- **AI Generation Telemetry**: Represents an audit log of AI model usage. Key attributes include model identifier, prompt tokens, completion tokens, calculated cost, and grounding status.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001 (Ingestion Reliability)**: 100% of valid Markdown and accessible web URLs are ingested and stored as single-source-of-truth records without data loss.
- **SC-002 (Constraint Enforcement)**: 100% of variants exceeding platform length or hashtag quotas are blocked from review with descriptive error messages.
- **SC-003 (Review Gate Integrity)**: Zero unapproved (`draft` or `rejected`) variants can be scheduled or dispatched; 100% of unapproved schedule attempts return HTTP 4xx.
- **SC-004 (Exactly-Once Publishing)**: 0% duplicate posts across identical slots under simulated network retries, duplicate requests, or worker crash-recovery cycles.
- **SC-005 (Adapter Independence)**: Platform adapters can be swapped or redirected via configuration changes with zero modifications to application domain code.
- **SC-006 (Audit Completeness)**: 100% of dispatch attempts produce a permanent audit history entry detailing execution outcome and external identifiers.

---

## Assumptions

- Target social platforms for initial deployment are Telegram (live channel), MockX (simulated local store), and MockLinkedIn (simulated local store).
- Real social network accounts on platforms that prohibit free automated bot posting (X/Twitter, LinkedIn, Instagram) are out of scope; mock adapters fulfill their architectural requirements.
- Multi-tenancy and agency client isolation are deferred out of scope per capstone boundaries.
- Database access and background queue persistence are provided by PostgreSQL and Oban within the Docker application container stack.

