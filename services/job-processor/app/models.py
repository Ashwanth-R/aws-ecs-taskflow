from __future__ import annotations

from pydantic import BaseModel, Field


class ProcessRequest(BaseModel):
    urls: list[str] = Field(min_length=1)
    job_id: str | None = None


class UrlCheck(BaseModel):
    url: str
    ok: bool
    status_code: int | None = None
    error: str | None = None


class ProcessResponse(BaseModel):
    total: int
    successful: int
    failed: int
    results: list[UrlCheck]
