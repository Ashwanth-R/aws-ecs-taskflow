from __future__ import annotations

import logging

import httpx
from fastapi import FastAPI, HTTPException, Request

from app.checker import check_urls
from app.config import Settings, get_settings
from app.logging import configure_logging
from app.models import ProcessRequest, ProcessResponse
from app.url_safety import UnsafeUrlError, validate_public_http_url

logger = logging.getLogger("job-processor")


def create_app(
    settings: Settings | None = None,
    http_client: httpx.Client | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    app = FastAPI(
        title="TaskFlow Job Processor",
        version="0.1.0",
        description="Internal service that checks a bounded list of public HTTP URLs.",
    )
    app.state.settings = settings
    app.state.http_client = http_client

    @app.get("/health")
    def health() -> dict[str, str]:
        """Liveness: the process is up. Keep this cheap for ECS health checks."""
        return {"status": "ok", "service": settings.service_name}

    @app.post("/process", response_model=ProcessResponse)
    def process(payload: ProcessRequest, request: Request) -> ProcessResponse:
        request_id = request.headers.get("x-request-id", "-")
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

        logger.info(
            "processing_urls job_id=%s request_id=%s count=%s",
            payload.job_id or "-",
            request_id,
            len(payload.urls),
        )

        owns_client = http_client is None
        client = http_client or httpx.Client()
        try:
            result = check_urls(
                payload.urls,
                client=client,
                url_timeout_seconds=settings.url_timeout_seconds,
                max_redirects=settings.max_redirects,
            )
        finally:
            if owns_client:
                client.close()

        logger.info(
            "processed_urls job_id=%s request_id=%s successful=%s failed=%s",
            payload.job_id or "-",
            request_id,
            result.successful,
            result.failed,
        )
        return result

    return app


app = create_app()
