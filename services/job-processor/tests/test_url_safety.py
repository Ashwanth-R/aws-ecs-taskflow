from __future__ import annotations

from unittest.mock import patch

import pytest

from app.url_safety import UnsafeUrlError, validate_public_http_url


def _addrinfo(ip: str, port: int = 443):
    return [(2, 1, 6, "", (ip, port))]


def test_rejects_non_http_scheme() -> None:
    with pytest.raises(UnsafeUrlError):
        validate_public_http_url("ftp://example.com/file")


def test_rejects_localhost() -> None:
    with pytest.raises(UnsafeUrlError):
        validate_public_http_url("http://localhost/secret")


def test_rejects_loopback_ip() -> None:
    with pytest.raises(UnsafeUrlError):
        validate_public_http_url("http://127.0.0.1/")


def test_rejects_private_ip() -> None:
    with pytest.raises(UnsafeUrlError):
        validate_public_http_url("http://10.0.0.5/admin")


def test_rejects_link_local_metadata() -> None:
    with pytest.raises(UnsafeUrlError):
        validate_public_http_url("http://169.254.169.254/latest/meta-data")


def test_rejects_resolved_private_ip() -> None:
    with patch("app.url_safety.socket.getaddrinfo", return_value=_addrinfo("192.168.1.10")):
        with pytest.raises(UnsafeUrlError):
            validate_public_http_url("http://internal.example.com/")


def test_allows_resolved_public_ip() -> None:
    with patch("app.url_safety.socket.getaddrinfo", return_value=_addrinfo("8.8.8.8")):
        validate_public_http_url("https://example.com/")
