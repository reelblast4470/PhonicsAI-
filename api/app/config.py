"""Environment-driven settings. Secrets NEVER have hard-coded production
values; the dev fallbacks are explicitly insecure and refused at boot when
ENVIRONMENT=production."""

import json
from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


def _origins_list(v):
    """Accept CORS_ORIGINS as a JSON list or a plain comma-separated string."""
    if isinstance(v, str):
        s = v.strip()
        if not s:
            return []
        if s.startswith("["):
            return json.loads(s)
        return [x.strip() for x in s.split(",") if x.strip()]
    return v

DEV_JWT_SECRET = "dev-only-insecure-change-me"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    environment: str = "dev"  # dev | staging | production
    database_url: str = "postgresql+asyncpg://phonicsai:devlocal_only_not_a_secret@127.0.0.1:5432/phonicsai"
    # Comma-separated ("a,b") or JSON (["a"]) — read via cors_origins_list.
    cors_origins: str = "http://localhost:8080"

    jwt_secret: str = DEV_JWT_SECRET
    jwt_audience: str = "phonicsai-api"
    access_token_minutes: int = 15
    learner_token_hours: int = 12
    refresh_token_days: int = 30

    email_verification_hours: int = 24
    password_reset_minutes: int = 60

    # Rate limits (slowapi syntax). Tight on auth, generous elsewhere.
    default_rate_limit: str = "120/minute"
    auth_rate_limit: str = "8/minute"
    login_rate_limit: str = "5/minute"
    trusted_proxy_hops: int = 0  # >0 only behind a proxy that sets X-Forwarded-For

    # Mail: 'outbox' writes .eml files under data/outbox (dev); 'console' logs.
    mail_mode: str = "outbox"
    outbox_dir: str = "data/outbox"
    app_public_base: str = "http://localhost:5173"  # links in emails

    max_event_batch: int = 50

    @property
    def cors_origins_list(self) -> list[str]:
        return _origins_list(self.cors_origins)

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    def validate_for_boot(self) -> None:
        if self.is_production:
            if self.jwt_secret == DEV_JWT_SECRET:
                raise RuntimeError(
                    "Refusing to start: JWT_SECRET is the dev default in production"
                )
            if "phonicsai:devlocal" in self.database_url:
                raise RuntimeError("Refusing to start: dev database credentials in production")


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    s.validate_for_boot()
    return s
