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
| Mastodon | 2,000 characters | Conversational, concise, and authentic | 5 |
| Mock X (Twitter) | 280 characters | Concise and direct | 2 |
| Mock LinkedIn | 3,000 characters | Professional and insight-oriented | 5 |

Hashtags count toward the platform's maximum length. A draft that exceeds its length or hashtag limit is invalid and cannot be approved until it is regenerated or edited. The profile definitions should be centralized so the same rules are used during generation, validation, and publication.

## 3. API / Core Surface

The core surface is organized around campaigns and their platform posts. JSON request and response shapes may evolve, but every mutating request should return stable resource identifiers and status information.

### Ingestion

- `POST /api/blog-posts` creates or ingests a source blog post.
- `POST /api/campaigns` creates a campaign from a blog post and requested target platforms.
- `GET /api/campaigns/:id` returns the campaign, source post, platform drafts, statuses, and validation results.
- `POST /api/campaigns/:id/regenerate` regenerates drafts using the selected constraint profiles.

Ingestion should accept an optional external source identifier. When supplied, that identifier can be used to safely retry ingestion without creating a duplicate source post.

### Review and Approval

- `GET /api/campaigns/:id/posts` lists the generated platform posts and their validation state.
- `PATCH /api/campaign-posts/:id` updates editable draft content or metadata while the post is in draft or rejected status.
- `POST /api/campaign-posts/:id/approve` approves a valid post for scheduling or immediate publication.
- `POST /api/campaign-posts/:id/reject` returns a post to the editing workflow with an optional review note.

Approval is a state transition, not a replacement for validation. The server must revalidate the final content and reject approval when the selected constraint profile is violated.

### Scheduling and Publishing

- `POST /api/campaign-posts/:id/publish` publishes an approved post immediately through its platform adapter.
- `POST /api/campaign-posts/:id/schedule` schedules an approved post for a specified time and timezone.
- `DELETE /api/campaign-posts/:id/schedule` cancels a pending schedule.

Publishing requests must accept an idempotency key, for example through the `Idempotency-Key` header. The key should be stored with the publication attempt and scoped to the campaign post. A repeated request with the same key returns the original result; a request that reuses the key with different content or target data returns a conflict. Platform adapters should also use their own external publication identifier when available.

### History Queries

- `GET /api/campaigns/:id/history` lists state changes, review actions, scheduled jobs, and publication attempts in chronological order.
- `GET /api/campaign-posts/:id/publications` lists all publication attempts and their external identifiers, response status, error details, and timestamps.

History is append-only from the API consumer's perspective. Failed retries should be visible without overwriting the original attempt, while an idempotent replay should reference the existing successful result instead of adding a duplicate publication.

## 4. Explicit Non-Goal

The first version does not include:

- Real Instagram or LinkedIn OAuth integration, account linking, or live production publishing.
- AI image generation or image asset creation.
- Analytics tracking, engagement collection, attribution, or performance dashboards.

The mock adapters and deterministic text transformation provide the foundation for those capabilities later without making them part of the initial delivery scope.
