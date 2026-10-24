from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings for the Task API.

    Values come from environment variables so the same image can run locally
    and later on ECS without hard-coded DNS names.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    service_name: str = "task-api"
    log_level: str = "INFO"
    processor_base_url: str = "http://localhost:8001"
    processor_timeout_seconds: float = 10.0
    max_urls_per_job: int = 10
    database_url: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
