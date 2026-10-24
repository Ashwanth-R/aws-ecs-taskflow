from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings for the Job Processor.

    This service stays private. The Task API will call it over Compose or
    Cloud Map DNS, configured through environment variables.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    service_name: str = "job-processor"
    log_level: str = "INFO"
    max_urls_per_job: int = 10
    url_timeout_seconds: float = 3.0
    max_redirects: int = 3


@lru_cache
def get_settings() -> Settings:
    return Settings()
