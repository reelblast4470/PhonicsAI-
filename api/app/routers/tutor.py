"""AI tutor endpoints (Phase 5 seam: the client's TutorService live adapter
talks here — and only here).

Design rules, enforced in code:

* The model context is built SERVER-side from the learner row + skill
  progress. The client sends the child's question, nothing else — no name,
  no age, no device data in the request body to leak or tamper with.
* A child-safety policy runs before the model: blocked-topic patterns get a
  deterministic, kind redirect with no model call at all, and off-topic
  model answers come back flagged. Flags are a parent-facing event, never a
  punishment: the exchange is stored for review.
* Free accounts get ``TUTOR_FREE_DAILY_MESSAGES`` exchanges/day (counted
  here, not client-side); a server-verified Plus subscription lifts the cap.
* Streaming is Server-Sent Events (``?sse=true``, the default) so any client
  — the Flutter app, the web reader, the admin console — can consume tokens
  with one small parser. ``?sse=false`` returns plain JSON.
"""

from __future__ import annotations

import json
from datetime import datetime, time, timezone
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, Response
from fastapi.responses import StreamingResponse
from sqlalchemy import func, select

from ..config import get_settings
from ..deps import ActorDep, Admin, DbSession, learner_for_actor
from ..errors import AppError
from ..ingestion.ai import AiError, get_ai_service
from ..limiter import TUTOR_LIMIT, limiter
from ..models import (Level, LearnerProfile, LearnerSkillProgress, ParentProfile,
                      Subscription, TutorExchange)
from ..schemas import TutorIn

router = APIRouter(prefix="/learners/{learner_id}/tutor", tags=["tutor"])
admin_router = APIRouter(prefix="/admin/tutor", tags=["admin"])


async def _plus_active(db, learner: LearnerProfile) -> bool:
    """Entitlement truth: the server-verified subscription only."""
    sub = await db.scalar(
        select(Subscription)
        .join(ParentProfile, ParentProfile.user_id == Subscription.user_id)
        .where(ParentProfile.id == learner.parent_id))
    if sub is None or not sub.verified or sub.status not in ("active", "trialing"):
        return False
    if sub.current_period_end is not None:
        return sub.current_period_end > datetime.now(timezone.utc)
    return True


async def _context(db, learner: LearnerProfile) -> dict:
    first = (learner.display_name or "friend").split(" ")[0]
    age = None
    if learner.birth_date:
        today = datetime.now(timezone.utc).date()
        age = max(3, (today - learner.birth_date).days // 365)
    level_label = "Sounds & symbols"
    key = learner.reading_level_key or learner.english_level_key
    if key:
        lvl = await db.scalar(select(Level).where(Level.key == key))
        if lvl:
            level_label = lvl.label
    # Struggling = attempted more than twice with <60% accuracy; recent = the
    # two most recently touched sounds. All derived from rows we already have.
    rows = (await db.execute(
        select(LearnerSkillProgress)
        .where(LearnerSkillProgress.learner_id == learner.id,
               LearnerSkillProgress.attempts >= 2)
        .order_by(LearnerSkillProgress.mastery.asc(),
                   LearnerSkillProgress.updated_at.desc())
        .limit(8))).scalars().all()
    struggling = [r.subject_key for r in rows if r.mastery < 0.6][:3]
    recent = [r.subject_key for r in
              sorted(rows, key=lambda r: r.updated_at, reverse=True)][:2]
    return {
        "learner_first_name": first,
        "age_years": age or 6,
        "level_label": level_label,
        "recent_phonemes": recent,
        "struggling_phonemes": struggling,
        "instruction_language": learner.preferred_language_code or "en",
    }


async def _quota_state(db, learner_id: UUID) -> tuple[bool, int]:
    s = get_settings()
    used = await db.scalar(
        select(func.count()).select_from(TutorExchange).where(
            TutorExchange.learner_id == learner_id,
            TutorExchange.created_at >= datetime.combine(
                datetime.now(timezone.utc).date(), time.min, tzinfo=timezone.utc)))
    return used < s.tutor_free_daily_messages, int(used or 0)


def _reply_dict(out: dict) -> dict:
    return {"text": out.get("text", ""), "chips": out.get("chips") or [],
            "action": out.get("action"), "flagged": bool(out.get("flagged"))}


@router.post("/reply", response_model=None)
@limiter.limit(TUTOR_LIMIT)
async def tutor_reply(learner_id: UUID, request: Request, response: Response,
                      body: TutorIn, db: DbSession, actor: ActorDep,
                      sse: Annotated[bool, Query()] = True):
    learner = await learner_for_actor(db, learner_id, actor)
    if not body.open_chat_allowed:
        raise AppError("tutor_chat_disabled",
                       "Free-typing to the tutor is turned off for this child. "
                       "The practice chips still work.", 403)
    plus = await _plus_active(db, learner)
    if not plus:
        within, used = await _quota_state(db, learner.id)
        if not within:
            raise AppError("tutor_quota_exceeded",
                           "You've used today's free tutor questions. They refresh "
                           "tomorrow — or a grown-up can add PhonicsAI Plus.", 429,
                           details=[f"free daily limit: {get_settings().tutor_free_daily_messages}"])

    message = body.message.strip()
    if len(message) > get_settings().tutor_max_message_chars:
        message = message[: get_settings().tutor_max_message_chars]
    ctx = await _context(db, learner)
    ai = get_ai_service()
    try:
        out = await ai.tutor_reply(message, ctx)
    except AiError as e:
        raise AppError("tutor_unavailable",
                       "The tutor is resting right now — try again in a moment.",
                       502) from e
    reply = _reply_dict(out)

    db.add(TutorExchange(
        learner_id=learner.id, question=message, answer=reply["text"],
        chips=reply["chips"], action=reply["action"],
        flagged=reply["flagged"], provider=ai.name, model=ai.model_version))
    await db.flush()

    if not sse:
        return reply

    async def stream():
        # The provider answers atomically; the server re-chunks it so the UI
        # can render token-by-token. (Upstream streaming is a later swap —
        # the wire format to clients does not change.)
        text = reply["text"]
        for i in range(0, len(text), 24):
            yield "event: token\ndata: " + json.dumps(
                {"text": text[i:i + 24]}, ensure_ascii=False) + "\n\n"
        yield "event: final\ndata: " + json.dumps(reply, ensure_ascii=False) + "\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-store",
                                      "X-Accel-Buffering": "no"})


@router.get("/starters")
async def tutor_starters(learner_id: UUID, db: DbSession, actor: ActorDep) -> dict:
    learner = await learner_for_actor(db, learner_id, actor)
    ctx = await _context(db, learner)
    ai = get_ai_service()
    return {"starters": await ai.tutor_starters(ctx)}


@router.get("/exchanges")
async def tutor_exchanges(learner_id: UUID, db: DbSession, actor: ActorDep,
                          limit: Annotated[int, Query(ge=1, le=100)] = 50) -> dict:
    """Thread for the family that owns the learner (parent dashboard shows
    'Aria was redirected N times' from this)."""
    learner = await learner_for_actor(db, learner_id, actor)
    rows = (await db.execute(
        select(TutorExchange).where(TutorExchange.learner_id == learner.id)
        .order_by(TutorExchange.created_at.desc()).limit(limit))).scalars().all()
    return {"exchanges": [{
        "id": str(r.id), "question": r.question, "answer": r.answer,
        "flagged": r.flagged, "chips": r.chips or [], "action": r.action,
        "provider": r.provider, "created_at": r.created_at.isoformat(),
    } for r in rows]}


@admin_router.get("/exchanges")
async def admin_exchanges(db: DbSession, admin: Admin,
                          learner_id: UUID | None = None,
                          flagged_only: bool = False,
                          limit: Annotated[int, Query(ge=1, le=200)] = 100) -> dict:
    q = select(TutorExchange, LearnerProfile.display_name).join(
        LearnerProfile, LearnerProfile.id == TutorExchange.learner_id)
    if learner_id:
        q = q.where(TutorExchange.learner_id == learner_id)
    if flagged_only:
        q = q.where(TutorExchange.flagged.is_(True))
    rows = (await db.execute(q.order_by(TutorExchange.created_at.desc())
                             .limit(limit))).all()
    return {"exchanges": [{
        "learner": name, "question": r.question, "answer": r.answer,
        "flagged": r.flagged, "provider": r.provider, "model": r.model,
        "created_at": r.created_at.isoformat(),
    } for r, name in rows]}
