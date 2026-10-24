from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse

from app.config import Settings, get_settings
from app.jobs import InMemoryJobStore, JobRecord, PostgresJobStore
from app.logging import configure_logging
from app.models import JobCreateRequest, JobResponse
from app.processor_client import HttpProcessorClient, ProcessorClient
from app.service import PersistenceError, submit_job
from app.url_safety import UnsafeUrlError, validate_public_http_url

logger = logging.getLogger("task-api")


def create_app(
    settings: Settings | None = None,
    job_store=None,
    processor_client: ProcessorClient | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        store = job_store or _build_store(settings)
        client = processor_client or HttpProcessorClient(
            settings.processor_base_url,
            settings.processor_timeout_seconds,
        )
        store.startup()
        app.state.job_store = store
        app.state.processor_client = client
        logger.info(
            "task_api_started store=%s processor_base_url=%s",
            type(store).__name__,
            settings.processor_base_url,
        )
        try:
            yield
        finally:
            store.shutdown()

    app = FastAPI(
        title="TaskFlow Task API",
        version="0.1.0",
        description="Public API for submitting URL-check jobs.",
        lifespan=lifespan,
    )
    app.state.settings = settings

    @app.get("/health")
    def health() -> dict[str, str]:
        """Liveness: the process is up. Keep this cheap for ECS/ALB checks."""
        return {"status": "ok", "service": settings.service_name}

    @app.get("/ready")
    def ready() -> JSONResponse:
        """Readiness: PostgreSQL must be reachable when a database is configured."""
        try:
            app.state.job_store.ping()
        except Exception:
            logger.warning("readiness_failed service=%s", settings.service_name)
            return JSONResponse(
                status_code=503,
                content={"status": "unavailable", "service": settings.service_name},
            )
        return JSONResponse(
            status_code=200,
            content={"status": "ok", "service": settings.service_name},
        )

    @app.post("/jobs", response_model=JobResponse)
    def create_job(payload: JobCreateRequest, request: Request) -> JobResponse:
        request_id = request.headers.get("x-request-id") or str(uuid4())
        if len(payload.urls) > settings.max_urls_per_job:
            raise HTTPException(
                status_code=422,
                detail=f"at most {settings.max_urls_per_job} URLs are allowed",
            )
        try:
            for url in payload.urls:
                validate_public_http_url(url)
        except UnsafeUrlError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

        try:
            job = submit_job(
                payload.urls,
                store=request.app.state.job_store,
                processor=request.app.state.processor_client,
                request_id=request_id,
            )
        except PersistenceError as exc:
            raise HTTPException(status_code=503, detail="could not persist job") from exc

        logger.info(
            "job_finished job_id=%s request_id=%s status=%s error_code=%s",
            job.id,
            request_id,
            job.status.value,
            job.error_code or "-",
        )
        return _to_response(job)

    @app.get("/jobs/{job_id}", response_model=JobResponse)
    def get_job(job_id: str) -> JobResponse:
        job = app.state.job_store.get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail="job not found")
        return _to_response(job)

    @app.get("/jobs", response_model=list[JobResponse])
    def list_jobs(
        limit: int = Query(default=20, ge=1, le=100),
        offset: int = Query(default=0, ge=0),
    ) -> list[JobResponse]:
        return [_to_response(job) for job in app.state.job_store.list(limit=limit, offset=offset)]

    return app


def _build_store(settings: Settings):
    if settings.database_url:
        return PostgresJobStore(settings.database_url)
    logger.warning("DATABASE_URL is empty; using in-memory job store")
    return InMemoryJobStore()


def _to_response(job: JobRecord) -> JobResponse:
    return JobResponse(
        job_id=job.id,
        status=job.status,
        result=job.result,
        error_code=job.error_code,
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


app = create_app()
