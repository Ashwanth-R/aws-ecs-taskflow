from fastapi.testclient import TestClient

from app.config import Settings
from app.jobs import InMemoryJobStore
from app.main import create_app
from app.processor_client import ProcessorClient
from app.models import JobResult


class UnusedProcessor(ProcessorClient):
    def process(self, urls: list[str], job_id: str, request_id: str) -> JobResult:
        raise AssertionError("processor should not be called for health checks")


def _make_app() -> TestClient:
    return TestClient(
        create_app(
            settings=Settings(log_level="WARNING"),
            job_store=InMemoryJobStore(),
            processor_client=UnusedProcessor(),
        )
    )


def test_health_returns_ok() -> None:
    with _make_app() as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "task-api"}


def test_ready_returns_ok() -> None:
    with _make_app() as client:
        response = client.get("/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "task-api"}
