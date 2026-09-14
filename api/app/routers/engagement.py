"""Achievements, feedback, notifications."""

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Request, Response
from sqlalchemy import select

from ..analytics import track
from ..limiter import FEEDBACK_LIMIT, limiter
from ..deps import ActorDep, DbSession, Parent, learner_for_actor
from ..errors import not_found
from ..models import (
    Achievement,
    Badge,
    Feedback,
    LearnerAchievement,
    Notification,
)
from ..schemas import AchievementOut, FeedbackIn, FeedbackOut, NotificationOut

router = APIRouter(tags=["engagement"])


@router.get("/learners/{learner_id}/achievements", response_model=list[AchievementOut])
async def learner_achievements(learner_id: UUID, actor: ActorDep, db: DbSession):
    learner = await learner_for_actor(db, learner_id, actor)
    earned = {r.achievement_id: r.earned_at for r in await db.scalars(
        select(LearnerAchievement).where(LearnerAchievement.learner_id == learner.id))}
    out = []
    for a in await db.scalars(select(Achievement)):
        out.append(AchievementOut(key=a.key, title=a.title, description=a.description,
                                  earned=a.id in earned, earned_at=earned.get(a.id)))
    return out


@router.get("/badges", response_model=list[dict])
async def badges(db: DbSession, actor: ActorDep):
    rows = list(await db.scalars(select(Badge)))
    return [{"key": b.key, "title": b.title, "icon": b.icon, "tier": b.tier} for b in rows]


@router.post("/feedback", response_model=FeedbackOut, status_code=201)
@limiter.limit(FEEDBACK_LIMIT)
async def submit_feedback(request: Request, response: Response, body: FeedbackIn, actor: ActorDep, db: DbSession):
    user_id = actor.parent.user.id if actor.parent else None
    learner_id = None
    if body.learner_id is not None:
        if actor.learner is not None and actor.learner.id != body.learner_id:
            raise not_found("Learner not found")
        if actor.parent is not None:
            await learner_for_actor(db, body.learner_id, actor)
        learner_id = body.learner_id
    row = Feedback(user_id=user_id, learner_id=learner_id, category=body.category,
                   message=body.message.strip())
    db.add(row)
    await track(db, "feedback_submitted", user_id=user_id,
                properties={"category": body.category})
    await db.flush()
    return FeedbackOut(id=row.id, category=row.category, status=row.status,
                       created_at=row.created_at)


@router.get("/feedback", response_model=list[FeedbackOut])
async def my_feedback(parent: Parent, db: DbSession):
    rows = list(await db.scalars(select(Feedback).where(
        Feedback.user_id == parent.user.id).order_by(Feedback.created_at.desc()).limit(50)))
    return [FeedbackOut.model_validate(r) for r in rows]


@router.get("/notifications", response_model=list[NotificationOut])
async def notifications(parent: Parent, db: DbSession):
    rows = list(await db.scalars(select(Notification).where(
        Notification.user_id == parent.user.id).order_by(Notification.created_at.desc()).limit(50)))
    return [NotificationOut.model_validate(r) for r in rows]


@router.post("/notifications/{notification_id}/read", status_code=204)
async def mark_read(notification_id: UUID, parent: Parent, db: DbSession):
    row = await db.get(Notification, notification_id)
    if row is None or row.user_id != parent.user.id:
        raise not_found("Notification not found")
    row.read_at = row.read_at or datetime.now(timezone.utc)
