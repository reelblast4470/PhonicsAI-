"""Batch analytics ingestion. Whitelisted event names, vetted properties,
authorization on learner ids (a parent may not emit for another family's
child — silently dropped rather than 404 to keep the beacon path cheap)."""

from fastapi import APIRouter
from sqlalchemy import select

from ..analytics import ALLOWED_EVENTS, track
from ..deps import ActorDep, DbSession
from ..models import LearnerProfile
from ..schemas import AnalyticsBatchIn

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.post("/events", response_model=dict)
async def ingest(body: AnalyticsBatchIn, actor: ActorDep, db: DbSession) -> dict:
    user_id = actor.parent.user.id if actor.parent else None
    own_learners: set = set()
    if actor.parent is not None:
        own_learners = {r for r in await db.scalars(select(LearnerProfile.id).where(
            LearnerProfile.parent_id == actor.parent.parent.id))}
    if actor.learner is not None:
        own_learners = {actor.learner.id}

    accepted = 0
    for ev in body.events:
        if ev.event not in ALLOWED_EVENTS:
            continue
        learner_id = ev.learner_id if ev.learner_id in own_learners else None
        await track(db, ev.event, user_id=user_id, learner_id=learner_id,
                    properties=ev.properties, platform=ev.platform,
                    app_version=ev.app_version)
        accepted += 1
    return {"accepted": accepted, "rejected": len(body.events) - accepted}
