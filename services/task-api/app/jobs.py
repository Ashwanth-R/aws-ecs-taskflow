from __future__ import annotations

import json
import threading
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Protocol
from uuid import uuid4

from app.models import JobResult, JobStatus


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


@dataclass(frozen=True)
class JobRecord:
    id: str
    status: JobStatus
    urls: list[str]
    result: JobResult | None
    error_code: str | None
    created_at: datetime
    updated_at: datetime


class JobStore(Protocol):
    def startup(self) -> None: ...

    def shutdown(self) -> None: ...

    def ping(self) -> None: ...

    def create(self, urls: list[str]) -> JobRecord: ...

    def save(self, job: JobRecord) -> JobRecord: ...

    def get(self, job_id: str) -> JobRecord | None: ...

    def list(self, limit: int, offset: int) -> list[JobRecord]: ...


class InMemoryJobStore:
    def __init__(self) -> None:
        self._jobs: dict[str, JobRecord] = {}
        self._lock = threading.Lock()

    def startup(self) -> None:
        return None

    def shutdown(self) -> None:
        return None

    def ping(self) -> None:
        return None

    def create(self, urls: list[str]) -> JobRecord:
        now = utcnow()
        job = JobRecord(
            id=str(uuid4()),
            status=JobStatus.PENDING,
            urls=urls,
            result=None,
            error_code=None,
            created_at=now,
            updated_at=now,
        )
        with self._lock:
            self._jobs[job.id] = job
        return job

    def save(self, job: JobRecord) -> JobRecord:
        updated = replace(job, updated_at=utcnow())
        with self._lock:
            if job.id not in self._jobs:
                raise KeyError(job.id)
            self._jobs[job.id] = updated
        return updated

    def get(self, job_id: str) -> JobRecord | None:
        with self._lock:
            return self._jobs.get(job_id)

    def list(self, limit: int, offset: int) -> list[JobRecord]:
        with self._lock:
            jobs = sorted(self._jobs.values(), key=lambda item: item.created_at, reverse=True)
        return jobs[offset : offset + limit]


class PostgresJobStore:
    def __init__(self, database_url: str) -> None:
        self._database_url = database_url
        self._pool = None

    def startup(self) -> None:
        from psycopg_pool import ConnectionPool

        self._pool = ConnectionPool(conninfo=self._database_url, min_size=1, max_size=5, open=True)
        self._apply_migrations()

    def shutdown(self) -> None:
        if self._pool is not None:
            self._pool.close()

    def ping(self) -> None:
        assert self._pool is not None
        with self._pool.connection() as conn:
            conn.execute("SELECT 1")

    def create(self, urls: list[str]) -> JobRecord:
        now = utcnow()
        job = JobRecord(
            id=str(uuid4()),
            status=JobStatus.PENDING,
            urls=urls,
            result=None,
            error_code=None,
            created_at=now,
            updated_at=now,
        )
        assert self._pool is not None
        with self._pool.connection() as conn:
            conn.execute(
                """
                INSERT INTO jobs (id, status, input_payload, result_payload, error_code, created_at, updated_at)
                VALUES (%s, %s, %s::jsonb, NULL, NULL, %s, %s)
                """,
                (job.id, job.status.value, json.dumps({"urls": urls}), job.created_at, job.updated_at),
            )
        return job

    def save(self, job: JobRecord) -> JobRecord:
        updated = replace(job, updated_at=utcnow())
        result_payload = json.dumps(job.result.model_dump()) if job.result is not None else None
        assert self._pool is not None
        with self._pool.connection() as conn:
            conn.execute(
                """
                UPDATE jobs
                SET status = %s,
                    result_payload = %s::jsonb,
                    error_code = %s,
                    updated_at = %s
                WHERE id = %s
                """,
                (
                    updated.status.value,
                    result_payload,
                    updated.error_code,
                    updated.updated_at,
                    updated.id,
                ),
            )
        return updated

    def get(self, job_id: str) -> JobRecord | None:
        assert self._pool is not None
        with self._pool.connection() as conn:
            row = conn.execute(
                """
                SELECT id, status, input_payload, result_payload, error_code, created_at, updated_at
                FROM jobs
                WHERE id = %s
                """,
                (job_id,),
            ).fetchone()
        return _row_to_job(row) if row else None

    def list(self, limit: int, offset: int) -> list[JobRecord]:
        assert self._pool is not None
        with self._pool.connection() as conn:
            rows = conn.execute(
                """
                SELECT id, status, input_payload, result_payload, error_code, created_at, updated_at
                FROM jobs
                ORDER BY created_at DESC
                LIMIT %s OFFSET %s
                """,
                (limit, offset),
            ).fetchall()
        return [_row_to_job(row) for row in rows]

    def _apply_migrations(self) -> None:
        assert self._pool is not None
        migrations_dir = Path(__file__).parent / "migrations"
        with self._pool.connection() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    version TEXT PRIMARY KEY,
                    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """
            )
            applied = {
                row[0]
                for row in conn.execute("SELECT version FROM schema_migrations").fetchall()
            }
            for path in sorted(migrations_dir.glob("*.sql")):
                if path.name in applied:
                    continue
                conn.execute(path.read_text())
                conn.execute(
                    "INSERT INTO schema_migrations (version) VALUES (%s)",
                    (path.name,),
                )


def _row_to_job(row: tuple) -> JobRecord:
    input_payload = row[2]
    result_payload = row[3]
    if isinstance(input_payload, str):
        input_payload = json.loads(input_payload)
    if isinstance(result_payload, str):
        result_payload = json.loads(result_payload)
    return JobRecord(
        id=str(row[0]),
        status=JobStatus(row[1]),
        urls=list(input_payload["urls"]),
        result=JobResult.model_validate(result_payload) if result_payload else None,
        error_code=row[4],
        created_at=row[5],
        updated_at=row[6],
    )
