# Social Studio Design

## 1. Problem Statement

Social Studio transforms a blog post into a coordinated social media campaign. A campaign contains platform-specific drafts derived from one source post, a review and approval workflow, optional publication schedules, and a history of publication attempts.

The transformation must be deterministic for the same source content and constraint profile. Publishing must be idempotent: retrying the same approved platform post with the same idempotency key must not create a duplicate publication or duplicate history entry. Each platform post should retain its source campaign, target platform, rendered content, status, and publication metadata.

The initial implementation uses mock platform adapters for development and demonstration. Platform constraints are applied before approval so reviewers see content that is ready for its target platform.

## 2. Constraint Profiles

Each platform profile defines the maximum rendered length, expected tone, and hashtag limit. The transformation pipeline should validate these constraints before a draft can be approved.

| Platform | Max length | Tone | Max hashtags |
| --- | ---: | --- | ---: |
| Telegram | 2,000 characters | Conversational and informative | 5 |
| Discord | 2,000 characters | Conversational, community-oriented, and informative | 5 |
| Mock X (Twitter) | 280 characters | Concise and direct | 2 |
| Mock LinkedIn | 3,000 characters | Professional and insight-oriented | 5 |

Hashtags count toward the platform's maximum length. A draft that exceeds its length or hashtag limit is invalid and cannot be approved until it is regenerated or edited. The profile definitions should be centralized so the same rules are used during generation, validation, and publication.

## 3. API / Core Surface

The core surface is organized around campaigns and their platform posts. JSON request and response shapes may evolve, but every mutating request should return stable resource identifiers and status information.

### Ingestion

- `POST /api/blog-posts` creates or ingests a source blog post.
- `GET /api/campaigns/:id` returns the campaign, source post, platform drafts, statuses, and validation results.

### Review and Approval

- `PATCH /api/campaign-posts/:id` updates editable draft content or metadata while the post is in draft or rejected status.
- `POST /api/campaign-posts/:id/approve` approves a variant for scheduling.
- `POST /api/campaign-posts/:id/reject` rejects a variant with a reason.

Approval is a state transition, not a replacement for validation. The server must revalidate the final content and reject approval when the selected constraint profile is violated.

### Scheduling and Publishing

- `POST /api/campaign-posts/:id/schedule` schedules an approved variant.
- `POST /api/slots/:id/publish` triggers immediate idempotent dispatch for a scheduled slot.

Publishing requests must accept an idempotency key, for example through the `Idempotency-Key` header. The key should be stored with the publication attempt and scoped to the campaign post. A repeated request with the same key returns the original result; a request that reuses the key with different content or target data returns a conflict. Platform adapters should also use their own external publication identifier when available.

### History Queries

- `GET /api/publishing/history` returns the audit trail of publication attempts, including external identifiers, response status, error details, and timestamps.

History is append-only from the API consumer's perspective. Failed retries should be visible without overwriting the original attempt, while an idempotent replay should reference the existing successful result instead of adding a duplicate publication.

## 4. Database and Publishing Workflow

```mermaid
sequenceDiagram
	autonumber
	actor User as User / API Client
	participant App as Phoenix App (Context)
	participant DB_Posts as DB: posts
	participant DB_Variants as DB: variants
	participant DB_Slots as DB: slots
	participant DB_Oban as DB: oban_jobs
	participant Worker as Oban.PublishWorker
	participant Platform as Platform API (Telegram/Discord/X)
	participant DB_Attempts as DB: publish_attempts

	%% Phase 1: Ingestion
	rect rgb(240, 244, 248)
	note right of User: Phase 1: Raw Ingestion
	User->>App: POST raw content / URL
	App->>DB_Posts: INSERT into posts (title, content, source_type)
	DB_Posts-->>App: %Post{id: post_id}
	end

	%% Phase 2: Transformation
	rect rgb(245, 240, 248)
	note right of User: Phase 2: Variant Transformation
	App->>DB_Variants: INSERT into variants (post_id, platform, content, status: "draft")
	DB_Variants-->>App: %Variant{id: variant_id}
	end

	%% Phase 3: Scheduling
	rect rgb(240, 248, 240)
	note right of User: Phase 3: Scheduling & Idempotency
	User->>App: Approve variant & pick scheduled_at
	App->>DB_Slots: INSERT into slots (variant_id, scheduled_at, idempotency_key, status: "pending")
	DB_Slots-->>App: %Slot{id: slot_id}
	App->>DB_Oban: INSERT into oban_jobs (args: %{slot_id: slot_id}, scheduled_at, state: "scheduled")
	DB_Oban-->>App: Job enqueued
	end

	%% Phase 4: Worker Execution & Audit Logging
	rect rgb(255, 248, 240)
	note right of Worker: Phase 4: Execution & Audit Logging
	Note over DB_Oban,Worker: At scheduled_at timestamp
	DB_Oban->>Worker: Pick up job %{slot_id: slot_id}
	Worker->>DB_Slots: Fetch Slot & associated ContentVariant
	Worker->>Platform: Send POST request (Payload + Idempotency Key)

	alt Request Successful
		Platform-->>Worker: HTTP 200 OK (external_post_id)
		Worker->>DB_Slots: UPDATE slots status = "completed"
		Worker->>DB_Attempts: INSERT into publish_attempts (slot_id, adapter_name, status: "success", response_payload)
		Worker->>DB_Oban: Mark job state = "completed"
	else Request Failed / Network Timeout
		Platform-->>Worker: HTTP Error / Timeout
		Worker->>DB_Attempts: INSERT into publish_attempts (slot_id, adapter_name, status: "error", error_message)
		Worker->>DB_Oban: Return {:error, reason} -> Trigger Oban Retry
	end
	end
```

## 5. Explicit Non-Goal

The first version does not include:

- Real Instagram or LinkedIn OAuth integration, account linking, or live production publishing.
- AI image generation or image asset creation.
- Analytics tracking, engagement collection, attribution, or performance dashboards.

The mock adapters and deterministic text transformation provide the foundation for those capabilities later without making them part of the initial delivery scope.
