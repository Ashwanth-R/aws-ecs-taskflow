from __future__ import annotations

import logging
from dataclasses import replace

from app.jobs import JobRecord, JobStore
from app.models import JobStatus
from app.processor_client import ProcessorClient, ProcessorError

logger = logging.getLogger("task-api")


class PersistenceError(Exception):
    error_code = "PERSISTENCE_ERROR"


def submit_job(
    urls: list[str],
    store: JobStore,
    processor: ProcessorClient,
    request_id: str,
) -> JobRecord:
    try:
        job = store.create(urls)
    except Exception as exc:
        raise PersistenceError("could not create job") from exc

    try:
        job = store.save(replace(job, status=JobStatus.PROCESSING))
    except Exception as exc:
        raise PersistenceError("could not update job") from exc

    try:
        result = processor.process(urls, job.id, request_id)
    except ProcessorError as exc:
        logger.warning(
            "processor_failed job_id=%s request_id=%s error_code=%s",
            job.id,
            request_id,
            exc.error_code,
        )
        return _fail(store, job, exc.error_code)

    try:
        return store.save(replace(job, status=JobStatus.COMPLETED, result=result, error_code=None))
    except Exception as exc:
        logger.error("persist_completed_failed job_id=%s request_id=%s", job.id, request_id)
        try:
            return _fail(store, job, PersistenceError.error_code)
        except Exception:
            raise PersistenceError("could not save job result") from exc


def _fail(store: JobStore, job: JobRecord, error_code: str) -> JobRecord:
    return store.save(replace(job, status=JobStatus.FAILED, error_code=error_code))
