from __future__ import annotations

from unittest.mock import patch

from fastapi.testclient import TestClient

from app.config import Settings
from app.jobs import InMemoryJobStore, JobRecord
from app.main import create_app
from app.models import JobResult, JobStatus, UrlCheck
from app.processor_client import ProcessorTimeout, ProcessorUnavailable


class FakeProcessor:
    def __init__(self, result: JobResult | None = None, error: Exception | None = None) -> None:
        self.result = result or JobResult(
            total=1,
            successful=1,
            failed=0,
            results=[UrlCheck(url="https://example.com", ok=True, status_code=200)],
        )
        self.error = error
        self.calls = 0

    def process(self, urls: list[str], job_id: str, request_id: str) -> JobResult:
        self.calls += 1
        if self.error is not None:
            raise self.error
        return self.result


class CompleteFailStore(InMemoryJobStore):
    def save(self, job: JobRecord) -> JobRecord:
        if job.status == JobStatus.COMPLETED:
            raise RuntimeError("disk full")
        return super().save(job)


def _make_app(store=None, processor=None, max_urls: int = 10) -> TestClient:
    return TestClient(
        create_app(
            settings=Settings(log_level="WARNING", max_urls_per_job=max_urls),
            job_store=store or InMemoryJobStore(),
            processor_client=processor or FakeProcessor(),
        )
    )


def test_create_job_success() -> None:
    with _make_app() as client:
        with patch("app.url_safety.socket.getaddrinfo", return_value=[(2, 1, 6, "", ("8.8.8.8", 443))]):
            response = client.post("/jobs", json={"urls": ["https://example.com"]})

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "COMPLETED"
    assert body["result"]["successful"] == 1
    assert body["error_code"] is None


def test_get_and_list_jobs() -> None:
    with _make_app() as client:
        with patch("app.url_safety.socket.getaddrinfo", return_value=[(2, 1, 6, "", ("8.8.8.8", 443))]):
            created = client.post("/jobs", json={"urls": ["https://example.com"]}).json()

        fetched = client.get(f"/jobs/{created['job_id']}")
        assert fetched.status_code == 200
        assert fetched.json()["job_id"] == created["job_id"]

        listed = client.get("/jobs")
        assert listed.status_code == 200
        assert listed.json()[0]["job_id"] == created["job_id"]


def test_processor_timeout_marks_failed() -> None:
    processor = FakeProcessor(error=ProcessorTimeout("slow"))
    with _make_app(processor=processor) as client:
        with patch("app.url_safety.socket.getaddrinfo", return_value=[(2, 1, 6, "", ("8.8.8.8", 443))]):
            response = client.post("/jobs", json={"urls": ["https://example.com"]})

    body = response.json()
    assert response.status_code == 200
    assert body["status"] == "FAILED"
    assert body["error_code"] == "PROCESSOR_TIMEOUT"
    assert body["result"] is None


def test_processor_unavailable_marks_failed() -> None:
    processor = FakeProcessor(error=ProcessorUnavailable("down"))
    with _make_app(processor=processor) as client:
        with patch("app.url_safety.socket.getaddrinfo", return_value=[(2, 1, 6, "", ("8.8.8.8", 443))]):
            response = client.post("/jobs", json={"urls": ["https://example.com"]})

    body = response.json()
    assert body["status"] == "FAILED"
    assert body["error_code"] == "PROCESSOR_UNAVAILABLE"


def test_persistence_error_does_not_mark_completed() -> None:
    store = CompleteFailStore()
    with _make_app(store=store, processor=FakeProcessor()) as client:
        with patch("app.url_safety.socket.getaddrinfo", return_value=[(2, 1, 6, "", ("8.8.8.8", 443))]):
            response = client.post("/jobs", json={"urls": ["https://example.com"]})

    body = response.json()
    assert response.status_code == 200
    assert body["status"] == "FAILED"
    assert body["error_code"] == "PERSISTENCE_ERROR"


def test_rejects_unsafe_url() -> None:
    with _make_app() as client:
        response = client.post("/jobs", json={"urls": ["http://127.0.0.1/"]})
    assert response.status_code == 422


def test_ready_returns_503_when_store_is_down() -> None:
    store = InMemoryJobStore()
    store.ping = lambda: (_ for _ in ()).throw(RuntimeError("db down"))  # type: ignore[method-assign]
    with _make_app(store=store) as client:
        response = client.get("/ready")
    assert response.status_code == 503
    assert response.json()["status"] == "unavailable"
