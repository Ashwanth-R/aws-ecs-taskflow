from __future__ import annotations

import logging

import httpx

from app.models import JobResult

logger = logging.getLogger("task-api")


class ProcessorError(Exception):
    error_code = "PROCESSOR_ERROR"


class ProcessorTimeout(ProcessorError):
    error_code = "PROCESSOR_TIMEOUT"


class ProcessorUnavailable(ProcessorError):
    error_code = "PROCESSOR_UNAVAILABLE"


class ProcessorRejected(ProcessorError):
    error_code = "PROCESSOR_REJECTED"


class ProcessorClient:
    def process(self, urls: list[str], job_id: str, request_id: str) -> JobResult:
        raise NotImplementedError


class HttpProcessorClient(ProcessorClient):
    def __init__(self, base_url: str, timeout_seconds: float, client: httpx.Client | None = None) -> None:
        self._base_url = base_url.rstrip("/")
        self._timeout = httpx.Timeout(timeout_seconds)
        self._client = client
        self._owns_client = client is None

    def process(self, urls: list[str], job_id: str, request_id: str) -> JobResult:
        client = self._client or httpx.Client()
        try:
            response = client.post(
                f"{self._base_url}/process",
                json={"urls": urls, "job_id": job_id},
                headers={"X-Request-ID": request_id},
                timeout=self._timeout,
            )
        except httpx.TimeoutException as exc:
            raise ProcessorTimeout("processor timed out") from exc
        except httpx.RequestError as exc:
            raise ProcessorUnavailable("processor is unavailable") from exc
        finally:
            if self._owns_client:
                client.close()

        if response.status_code == 422:
            raise ProcessorRejected("processor rejected the request")
        if response.status_code >= 400:
            logger.warning(
                "processor_error job_id=%s request_id=%s status=%s",
                job_id,
                request_id,
                response.status_code,
            )
            raise ProcessorError("processor returned an error")
        return JobResult.model_validate(response.json())
