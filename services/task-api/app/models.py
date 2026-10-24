from __future__ import annotations

from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field


class JobStatus(str, Enum):
    PENDING = "PENDING"
    PROCESSING = "PROCESSING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"


class JobCreateRequest(BaseModel):
    urls: list[str] = Field(min_length=1)


class UrlCheck(BaseModel):
    url: str
    ok: bool
    status_code: int | None = None
    error: str | None = None


class JobResult(BaseModel):
    total: int
    successful: int
    failed: int
    results: list[UrlCheck] = Field(default_factory=list)


class JobResponse(BaseModel):
    job_id: str
    status: JobStatus
    result: JobResult | None = None
    error_code: str | None = None
    created_at: datetime
    updated_at: datetime
