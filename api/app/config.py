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

    # ---- Phase 4: AI content-intelligence pipeline ------------------------
    # Provider abstraction: 'mock' is deterministic + free and ships as the
    # default; real providers need a key (backend-side only, never in the
    # client). Costs are estimates used for budget visibility, not billing.
    ai_provider: str = "mock"           # mock | gemini | openai_compatible
    ai_model: str = ""                  # "" -> provider default (recorded)
    ai_api_key: str = ""                # from env only — never logged, never sent out
    ai_base_url: str = ""               # openai_compatible: https://…/v1
    ai_request_timeout_s: int = 120
    ai_cost_input_per_1m_usd: float = 0.0    # advisory cost estimate
    ai_cost_output_per_1m_usd: float = 0.0
    ai_max_chunks_per_job: int = 240    # cost guard: process head, flag the rest
    ai_chunk_min_tokens: int = 500
    ai_chunk_max_tokens: int = 1000
    knowledge_min_confidence: float = 0.45
    verbatim_max_words: int = 20        # >= this many consecutive words from a
                                        # source in generated content -> blocked

    # ---- Phase 5: store verification + AI tutor --------------------------
    billing_mode: str = "mock"            # mock | google_play | app_store | off
    google_package: str = ""              # applicationId from Play Console
    google_access_token: str = ""         # ops-minted androidpublisher OAuth token
    appstore_shared_secret: str = ""
    appstore_sandbox: bool = False
    tutor_free_daily_messages: int = 3    # per learner, UTC day, server-counted
    tutor_max_message_chars: int = 600

    uploads_dir: str = "data/uploads"
    upload_max_mb: int = 25
    upload_zip_max_uncompressed_mb: int = 60   # zip-bomb guard for docx/epub
    ocr_command: str = ""   # optional shell hook: "ocr-extract {pdf} {out.txt}"

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
        if self.ai_provider not in ("mock", "gemini", "openai_compatible"):
            raise RuntimeError(f"Unknown AI_PROVIDER={self.ai_provider!r}")
        if self.ai_provider in ("gemini", "openai_compatible") and not self.ai_api_key:
            raise RuntimeError(f"AI_PROVIDER={self.ai_provider} requires AI_API_KEY")
        if self.billing_mode not in ("mock", "google_play", "app_store", "off"):
            raise RuntimeError(f"Unknown BILLING_MODE={self.billing_mode!r}")
        if self.is_production and self.billing_mode == "mock":
            raise RuntimeError(
                "Refusing to start: BILLING_MODE=mock would accept fake receipts "
                "in production - use google_play/app_store or 'off'")


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    s.validate_for_boot()
    return s
