from __future__ import annotations

import ipaddress
import socket
from urllib.parse import urlparse

BLOCKED_HOSTS = {
    "localhost",
    "localhost.localdomain",
    "metadata.google.internal",
    "metadata.goog",
}

BLOCKED_HOST_SUFFIXES = (".localhost", ".local", ".internal")


class UnsafeUrlError(ValueError):
    """Raised when a URL is not safe to fetch (scheme, host, or resolved IP)."""


def validate_public_http_url(url: str) -> None:
    """Reject URLs that could be used for SSRF.

    Checks scheme, blocks obvious metadata/localhost names, resolves DNS,
    and refuses loopback, private, link-local, and other non-public IPs.
    Call this again for every redirect target.
    """
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise UnsafeUrlError("only http and https URLs are allowed")
    if parsed.username or parsed.password:
        raise UnsafeUrlError("URLs with credentials are not allowed")
    hostname = parsed.hostname
    if not hostname:
        raise UnsafeUrlError("URL must include a hostname")

    hostname = hostname.lower().rstrip(".")
    if hostname in BLOCKED_HOSTS or hostname.endswith(BLOCKED_HOST_SUFFIXES):
        raise UnsafeUrlError("hostname is not allowed")

    try:
        literal_ip = ipaddress.ip_address(hostname)
    except ValueError:
        literal_ip = None

    if literal_ip is not None:
        _assert_public_ip(literal_ip)
        return

    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        addrinfo = socket.getaddrinfo(hostname, port, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        raise UnsafeUrlError("hostname could not be resolved") from exc

    if not addrinfo:
        raise UnsafeUrlError("hostname could not be resolved")

    for info in addrinfo:
        _assert_public_ip(ipaddress.ip_address(info[4][0]))


def _assert_public_ip(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> None:
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped is not None:
        _assert_public_ip(ip.ipv4_mapped)
        return

    if (
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_reserved
        or ip.is_unspecified
    ):
        raise UnsafeUrlError("URL resolves to a non-public address")
