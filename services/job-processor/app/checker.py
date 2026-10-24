from __future__ import annotations

from urllib.parse import urljoin

import httpx

from app.models import ProcessResponse, UrlCheck
from app.url_safety import UnsafeUrlError, validate_public_http_url


def check_urls(
    urls: list[str],
    client: httpx.Client,
    url_timeout_seconds: float,
    max_redirects: int,
) -> ProcessResponse:
    results = [
        check_one_url(url, client, url_timeout_seconds, max_redirects) for url in urls
    ]
    successful = sum(1 for item in results if item.ok)
    return ProcessResponse(
        total=len(results),
        successful=successful,
        failed=len(results) - successful,
        results=results,
    )


def check_one_url(
    url: str,
    client: httpx.Client,
    url_timeout_seconds: float,
    max_redirects: int,
) -> UrlCheck:
    current = url
    try:
        for _ in range(max_redirects + 1):
            validate_public_http_url(current)
            response = client.get(
                current,
                follow_redirects=False,
                timeout=httpx.Timeout(url_timeout_seconds),
            )
            if response.is_redirect:
                location = response.headers.get("location")
                if not location:
                    return UrlCheck(
                        url=url, ok=False, status_code=response.status_code, error="redirect_missing_location"
                    )
                current = urljoin(current, location)
                continue
            return UrlCheck(url=url, ok=response.is_success, status_code=response.status_code)
        return UrlCheck(url=url, ok=False, error="too_many_redirects")
    except UnsafeUrlError as exc:
        return UrlCheck(url=url, ok=False, error=str(exc))
    except httpx.TimeoutException:
        return UrlCheck(url=url, ok=False, error="timeout")
    except httpx.RequestError:
        return UrlCheck(url=url, ok=False, error="request_failed")
