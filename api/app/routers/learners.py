"""Learner profile CRUD, strictly under the authenticated parent."""

from uuid import UUID

from fastapi import APIRouter, status
from sqlalchemy import func, select

from ..analytics import track
from ..deps import DbSession, Parent, require_parent_owns
from ..errors import AppError
from ..models import LearnerProfile, Streak
from ..schemas import LearnerCreateIn, LearnerOut, LearnerUpdateIn

router = APIRouter(prefix="/learners", tags=["learners"])

MAX_LEARNERS = 8


async def _out(db, learner: LearnerProfile) -> LearnerOut:
    streak = await db.get(Streak, learner.id)
    return LearnerOut(
        id=learner.id, display_name=learner.display_name, birth_date=learner.birth_date,
        preferred_language_code=learner.preferred_language_code,
        english_level_key=learner.english_level_key,
        reading_level_key=learner.reading_level_key,
        learning_goals=learner.learning_goals or {},
        daily_target_minutes=learner.daily_target_minutes,
        xp=learner.xp, stars=learner.stars,
        streak_current=streak.current if streak else 0,
        streak_longest=streak.longest if streak else 0,
        current_lesson_id=learner.current_lesson_id,
        avatar_key=learner.avatar_key, archived=learner.archived,
        updated_at=learner.updated_at,
    )


@router.get("", response_model=list[LearnerOut])
async def list_learners(parent: Parent, db: DbSession) -> list[LearnerOut]:
    rows = list(await db.scalars(
        select(LearnerProfile)
        .where(LearnerProfile.parent_id == parent.parent.id,
               LearnerProfile.archived.is_(False))
        .order_by(LearnerProfile.created_at)
    ))
    return [await _out(db, r) for r in rows]


@router.post("", response_model=LearnerOut, status_code=status.HTTP_201_CREATED)
async def create_learner(body: LearnerCreateIn, parent: Parent, db: DbSession) -> LearnerOut:
    count = await db.scalar(
        select(func.count(LearnerProfile.id)).where(
            LearnerProfile.parent_id == parent.parent.id,
            LearnerProfile.archived.is_(False),
        )
    )
    if (count or 0) >= MAX_LEARNERS:
        raise AppError("too_many_learners", f"A family can have at most {MAX_LEARNERS} learners")
    learner = LearnerProfile(
        parent_id=parent.parent.id, display_name=body.display_name.strip(),
        birth_date=body.birth_date, preferred_language_code=body.preferred_language_code,
        daily_target_minutes=body.daily_target_minutes, avatar_key=body.avatar_key,
        learning_goals=body.learning_goals,
    )
    db.add(learner)
    await db.flush()
    db.add(Streak(learner_id=learner.id))
    return await _out(db, learner)


@router.get("/{learner_id}", response_model=LearnerOut)
async def get_learner(learner_id: UUID, parent: Parent, db: DbSession) -> LearnerOut:
    learner = await require_parent_owns(db, parent, learner_id)
    return await _out(db, learner)


@router.patch("/{learner_id}", response_model=LearnerOut)
async def update_learner(learner_id: UUID, body: LearnerUpdateIn, parent: Parent, db: DbSession) -> LearnerOut:
    learner = await require_parent_owns(db, parent, learner_id)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(learner, field, value)
    await db.flush()
    return await _out(db, learner)


@router.delete("/{learner_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_learner(learner_id: UUID, parent: Parent, db: DbSession) -> None:
    """Hard delete: a removed child's data is gone, not hidden (DB cascade)."""
    learner = await require_parent_owns(db, parent, learner_id)
    await db.delete(learner)
