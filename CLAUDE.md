# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

TaskFlow is a two-service learning project for AWS ECS. The goal is understanding ECS infrastructure, not building a product. Read `AGENTS.md` before making any changes — it governs the milestone-by-milestone approval process and operating rules.

**Current status (as of Milestone 2):** Local skeleton is complete. Both services run in Docker Compose with PostgreSQL. AWS deployment has not started.

## Commands

### Docker Compose (recommended for full-stack local work)

```bash
docker compose up --build           # start all services
docker compose down                 # stop and remove containers
docker compose logs -f task-api     # follow logs for one service
```

### Run a service without Docker

```bash
cd services/task-api
source .venv/bin/activate
uvicorn app.main:app --reload --port 8000

cd services/job-processor
source .venv/bin/activate
uvicorn app.main:app --reload --port 8001
```

### Tests

```bash
cd services/task-api && python -m pytest
cd services/job-processor && python -m pytest
python -m pytest tests/test_health.py   # single test file (run from service dir)
python -m pytest -k test_submit_job     # single test by name
```

### Install dev dependencies

```bash
cd services/task-api && pip install -r requirements-dev.txt
cd services/job-processor && pip install -r requirements-dev.txt
```

### Build images individually

```bash
docker build -t taskflow-task-api ./services/task-api
docker build -t taskflow-job-processor ./services/job-processor
```

## Architecture

Two FastAPI services communicate synchronously over HTTP (HTTP is intentional to teach service discovery; async/SQS is a later milestone):

- **Task API** (`services/task-api/`, port 8000) — public-facing. Accepts `POST /jobs`, validates URLs, persists job records in PostgreSQL, calls the processor, and updates the record with the result. Exposes `GET /jobs/{id}`, `GET /jobs`, `GET /health`, `GET /ready`.
- **Job Processor** (`services/job-processor/`, port 8001) — internal only. Accepts `POST /process` with a URL list, checks each URL with timeouts and SSRF guards, returns a summary. Exposes `GET /health`.

Locally the API reaches the processor at `http://job-processor:8001` (Docker Compose DNS). On ECS this becomes a private AWS Cloud Map DNS name configured through the `PROCESSOR_BASE_URL` env var.

### Key files

| Path | Purpose |
|---|---|
| `services/task-api/app/main.py` | FastAPI app factory; routes wired here |
| `services/task-api/app/service.py` | `submit_job` — job lifecycle and status transitions |
| `services/task-api/app/jobs.py` | `JobStore` protocol + `InMemoryJobStore` + `PostgresJobStore` |
| `services/task-api/app/processor_client.py` | HTTP client for calling the processor |
| `services/task-api/app/url_safety.py` | SSRF validation shared by both services |
| `services/task-api/app/migrations/` | SQL migration files (auto-applied on startup) |
| `services/job-processor/app/checker.py` | URL checking logic (keep external HTTP mocked in tests) |
| `services/job-processor/app/url_safety.py` | Duplicate of Task API's SSRF validation (each service validates independently) |
| `docker-compose.yml` | Wires postgres + task-api + job-processor on the `taskflow` network |

### Job status flow

`PENDING` → `PROCESSING` → `COMPLETED` or `FAILED`

Status is set by `submit_job` in `service.py`. A job is only marked `COMPLETED` if both the processor call and the final `store.save()` succeed.

### Database

PostgreSQL is owned exclusively by the Task API. Schema is applied at startup from `services/task-api/app/migrations/*.sql` via `PostgresJobStore._apply_migrations()`. When `DATABASE_URL` is not set, `InMemoryJobStore` is used as a fallback (tests use this).

### Testing approach

- Both services use `create_app()` factory functions so tests can inject a fake `JobStore` and fake `ProcessorClient`/`httpx.Client`.
- Do not make real external HTTP calls in tests — mock `httpx.Client` or use `respx`/`pytest-httpx`.
- Tests live in `services/<service>/tests/`.

## Environment variables

See `.env.example` for the full list. Key variables:

| Variable | Service | Default | Notes |
|---|---|---|---|
| `PROCESSOR_BASE_URL` | task-api | `http://localhost:8001` | Compose overrides to `http://job-processor:8001` |
| `DATABASE_URL` | task-api | _(empty)_ | Falls back to in-memory store if unset |
| `PROCESSOR_TIMEOUT_SECONDS` | task-api | `10` | |
| `MAX_URLS_PER_JOB` | both | `10` | |
| `URL_TIMEOUT_SECONDS` | job-processor | `3` | Per-URL HTTP timeout |

Copy `.env.example` to `.env` for local overrides; `.env` is gitignored and must not be committed.

## Approval protocol

Before each milestone, follow the inspect → plan → wait → implement → verify → report cycle in `AGENTS.md`. Do not proceed to the next milestone without explicit user approval.
