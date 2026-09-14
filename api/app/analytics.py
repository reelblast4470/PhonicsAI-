"""Analytics ingestion with a whitelist — telemetry the product actually
reads, and nothing else (no free text, no PII)."""

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from .models import AnalyticsEvent

ALLOWED_EVENTS: frozenset[str] = frozenset({
    "registration",
    "email_verified",
    "onboarding_completed",
    "assessment_started",
    "assessment_completed",
    "lesson_started",
    "lesson_completed",
    "lesson_abandoned",
    "question_answered",
    "game_started",
    "game_completed",
    "daily_task_completed",
    "ai_tutor_used",
    "pronunciation_practice",
    "reading_practice",
    "streak_extended",
    "streak_lost",
    "subscription_started",
    "subscription_cancelled",
    "subscription_renewed",
    "feedback_submitted",
    "account_deleted",
})


async def track(
    db: AsyncSession,
    event: str,
    *,
    user_id: UUID | None = None,
    learner_id: UUID | None = None,
    properties: dict | None = None,
    platform: str | None = None,
    app_version: str | None = None,
) -> None:
    if event not in ALLOWED_EVENTS:
        return
    db.add(
        AnalyticsEvent(
            event=event,
            user_id=user_id,
            learner_id=learner_id,
            properties=properties or {},
            platform=platform,
            app_version=app_version,
        )
    )
