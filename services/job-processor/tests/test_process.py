from __future__ import annotations

from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def _client(handler) -> TestClient:
    transport = httpx.MockTransport(handler)
    http_client = httpx.Client(transport=transport)
    settings = Settings(log_level="WARNING", max_urls_per_job=3, url_timeout_seconds=1)
    return TestClient(create_app(settings=settings, http_client=http_client))


def test_process_success_with_mocked_http() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text="ok")

    with patch("app.url_safety.socket.getaddrinfo", return_value=[(2, 1, 6, "", ("8.8.8.8", 443))]):
        response = _client(handler).post("/process", json={"urls": ["https://example.com"]})

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["successful"] == 1
    assert body["failed"] == 0
    assert body["results"][0]["ok"] is True
    assert body["results"][0]["status_code"] == 200


def test_process_rejects_too_many_urls() -> None:
    response = _client(lambda request: httpx.Response(200)).post(
        "/process",
        json={"urls": ["https://example.com/a", "https://example.com/b", "https://example.com/c", "https://example.com/d"]},
    )
    assert response.status_code == 422


def test_process_rejects_private_url_before_fetch() -> None:
    fetched = {"called": False}

    def handler(request: httpx.Request) -> httpx.Response:
        fetched["called"] = True
        return httpx.Response(200)

    response = _client(handler).post("/process", json={"urls": ["http://127.0.0.1/"]})
    assert response.status_code == 422
    assert fetched["called"] is False


def test_process_blocks_redirect_to_private_ip() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "example.com":
            return httpx.Response(302, headers={"location": "http://127.0.0.1/secret"})
        return httpx.Response(200)

    with patch("app.url_safety.socket.getaddrinfo", return_value=[(2, 1, 6, "", ("8.8.8.8", 443))]):
        response = _client(handler).post("/process", json={"urls": ["https://example.com"]})

    assert response.status_code == 200
    body = response.json()
    assert body["successful"] == 0
    assert body["failed"] == 1
    assert "non-public" in body["results"][0]["error"] or "not allowed" in body["results"][0]["error"]
