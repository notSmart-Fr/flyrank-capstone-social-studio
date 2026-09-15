# Social Studio - Multi-Platform Content Ingestion & Publishing Studio

Social Studio is an Elixir/Phoenix API that ingests long-form blog content, generates platform-tailored social media drafts (Telegram, Mock X, Mock LinkedIn), enforces strict constraint rules, provides a human review workflow, and dispatches posts using an idempotent, durable background worker.

---

## Architecture Overview

- **`Content` Context:** Manages raw blog post ingestion, variant generation, and constraint profile validation.
- **`Publishing` Context:** Manages scheduling slots, Oban durable workers, platform publisher adapters, and idempotency checks.

---

## Quick Start (Docker)

### Prerequisites

- Docker Desktop with Docker Compose
- Ports `4000` and `5432` available

### Start the Application

From the repository root, build the Phoenix image and start PostgreSQL and the API:

```bash
docker compose up --build
```

Compose starts the `db` service first and waits for PostgreSQL to become healthy before starting the `app` service. The API will then be available at `http://localhost:4000`.

To start the services in the background:

```bash
docker compose up --build -d
```

Check the service status and follow application logs with:

```bash
docker compose ps
docker compose logs -f app
```

To stop the containers while keeping the PostgreSQL data volume:

```bash
docker compose down
```

To stop the containers and remove the PostgreSQL data volume, useful for a clean database reset:

```bash
docker compose down -v
```

The Compose configuration provides the production database URL and Phoenix port automatically. Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in a `.env` file in the repository root when using the live Telegram adapter.

## Quick Start (Local Development)

### Prerequisites

- Elixir 1.20.4 and Erlang/OTP 29
- PostgreSQL 16+

### Setup

1. Clone the repository and install dependencies:

	```bash
	mix deps.get
	```

2. Set the required environment variables from `.env.example`.

3. Set up the database and run migrations:

	```bash
	mix ecto.setup
	```

4. Run the Phoenix server:

	```bash
	mix phx.server
	```

5. Run the full ExUnit test suite:

	```bash
	mix test
	```

## API Endpoints

| Method | Endpoint | Description |
| --- | --- | --- |
| `POST` | `/api/blog-posts` | Ingests a blog post and generates draft variants. |
| `GET` | `/api/campaigns/:id` | Returns a campaign post with variants and slots. |
| `PATCH` | `/api/campaign-posts/:id` | Edits variant content. |
| `POST` | `/api/campaign-posts/:id/approve` | Approves a variant for scheduling. |
| `POST` | `/api/campaign-posts/:id/reject` | Rejects a variant with a reason. |
| `POST` | `/api/campaign-posts/:id/schedule` | Schedules an approved variant. |
| `POST` | `/api/slots/:id/publish` | Triggers immediate idempotent dispatch. |
| `GET` | `/api/publishing/history` | Returns the audit trail of publication attempts. |
