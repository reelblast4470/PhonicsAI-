"""The learning-data API: sessions, the event ledger, completion, snapshots,
daily tasks.

Trust model: the client reports *attempts*, the server decides *correctness*
(answers live only here) and *awards* (the progress engine). A crafted client
cannot grant itself XP: payload["correct"] is overwritten from the database.
"""

from datetime import date, datetime, timezone
from uuid import UUID

from fastapi import APIRouter
from sqlalchemy import func, select

from ..analytics import track
from ..deps import ActorDep, DbSession, learner_for_actor
from ..errors import AppError, not_found
from ..models import (
    Answer,
    LearnerSkillProgress,
    DailyTask,
    LearningEvent,
    LearningSession,
    Lesson,
    Question,
    Streak,
)
from ..progress import (
    apply_srs,
    bump_daily_tasks,
    bump_streak,
    check_achievements,
    ensure_daily_tasks,
    next_best_lesson,
    stars_for_lesson,
    xp_for_event,
)
from ..schemas import (
    DailyTaskOut,
    MasteryRowOut,
    RecommendationOut,
    ReviewItemOut,
    EventIn,
    LessonCompleteIn,
    SessionOut,
    SessionStartIn,
    SnapshotOut,
)

router = APIRouter(prefix="/learners/{learner_id}", tags=["progress"])


@router.post("/sessions", response_model=SessionOut, status_code=201)
async def start_session(learner_id: UUID, body: SessionStartIn,
                        actor: ActorDep, db: DbSession) -> SessionOut:
    learner = await learner_for_actor(db, learner_id, actor)
    if body.kind == "lesson":
        if body.ref_id is None:
            raise AppError("lesson_ref_required", "lesson sessions need ref_id")
        lesson = await db.get(Lesson, body.ref_id)
        if lesson is None:
            raise not_found("Lesson not found")
        learner.current_lesson_id = lesson.id
        await track(db, "lesson_started", learner_id=learner.id,
                    properties={"lesson_id": str(lesson.id)})
    elif body.kind == "game":
        await track(db, "game_started", learner_id=learner.id,
                    properties={"game": body.ref_key})
    # materialize today's tasks on first activity
    await ensure_daily_tasks(db, learner, datetime.now(timezone.utc).date())

    session = LearningSession(learner_id=learner.id, kind=body.kind,
                              ref_id=body.ref_id, ref_key=body.ref_key)
    db.add(session)
    await db.flush()
    return SessionOut(id=session.id, kind=session.kind, status=session.status,
                      started_at=session.started_at, xp_awarded=0, stars=0, accuracy=None)


@router.post("/sessions/{session_id}/events", response_model=dict)
async def add_event(learner_id: UUID, session_id: UUID, body: EventIn,
                    actor: ActorDep, db: DbSession) -> dict:
    learner = await learner_for_actor(db, learner_id, actor)
    session = await db.get(LearningSession, session_id)
    if session is None or session.learner_id != learner.id:
        raise not_found("Session not found")
    if session.status != "active":
        raise AppError("session_closed", "This session is already finished")

    payload = dict(body.payload)

    # Server-authoritative correctness for question events.
    if body.event_type in ("question_answered", "answer_wrong"):
        qid, aid = payload.get("question_id"), payload.get("answer_id")
        try:
            question_uuid, answer_uuid = UUID(str(qid)), UUID(str(aid))
        except (TypeError, ValueError):
            raise AppError("invalid_ids", "question_id and answer_id must be UUIDs") from None
        answer = await db.get(Answer, answer_uuid)
        if answer is None or answer.question_id != question_uuid:
            raise not_found("Answer is not valid for that question")
        payload["question_id"] = str(question_uuid)
        payload["answer_id"] = str(answer_uuid)
        payload["correct"] = bool(answer.is_correct)

    # Idempotent replay: same client_event_id → same effect, zero side changes.
    if body.client_event_id:
        dup = await db.scalar(select(LearningEvent).where(
            LearningEvent.client_event_id == body.client_event_id))
        if dup is not None:
            return {"ok": True, "duplicate": True, "xp_awarded": dup.xp_delta,
                    "correct": dup.payload.get("correct"),
                    "correct_answer_id": dup.payload.get("correct_answer_id"),
                    "explanation": dup.payload.get("explanation")}

    verdict: dict = {}
    if body.event_type == "question_answered":
        question = await db.get(Question, question_uuid)
        correct_row = await db.scalar(select(Answer).where(
            Answer.question_id == question_uuid, Answer.is_correct.is_(True)))
        chosen = await db.get(Answer, answer_uuid)
        payload["correct_answer_id"] = str(correct_row.id) if correct_row else None
        verdict = {
            "correct": bool(payload.get("correct")),
            "correct_answer_id": payload["correct_answer_id"],
            "correct_text": correct_row.text if correct_row else None,
            "explanation": (question.explanation if question else None),
            "chosen_feedback": None if payload.get("correct") else (
                chosen.feedback if chosen else None),
        }

    xp = xp_for_event(body.event_type, payload)
    event = LearningEvent(learner_id=learner.id, session_id=session.id,
                          event_type=body.event_type, payload=payload,
                          client_event_id=body.client_event_id, xp_delta=xp)
    db.add(event)
    session.xp_awarded += xp
    learner.xp += xp

    today = datetime.now(timezone.utc).date()
    streak, extended, lost = await bump_streak(db, learner, today)
    if extended:
        await track(db, "streak_extended", learner_id=learner.id,
                    properties={"current": streak.current})
    elif lost:
        await track(db, "streak_lost", learner_id=learner.id)

    if body.event_type in ("question_answered", "review_graded"):
        if body.event_type == "review_graded":
            correct = int(payload.get("grade", 0)) >= 3
            subject = str(payload.get("phoneme") or "general")
            skill = "phonics"
        else:
            correct = bool(payload.get("correct"))
            subject = str(payload.get("phoneme") or payload.get("subject") or "general")
            skill = "phonics" if subject != "general" else "reading"
        await apply_srs(db, learner.id, skill_key=skill, subject_key=subject,
                        correct=correct)
    if body.event_type == "game_completed":
        await track(db, "game_completed", learner_id=learner.id,
                    properties={"game": payload.get("game"), "score": payload.get("score")})
    if body.event_type == "pronunciation_practiced":
        await track(db, "pronunciation_practice", learner_id=learner.id,
                    properties={"score": payload.get("score")})
    if body.event_type == "reading_practiced":
        await track(db, "reading_practice", learner_id=learner.id,
                    properties={"minutes": payload.get("minutes")})
    if body.event_type in ("question_answered",):
        await track(db, "question_answered", learner_id=learner.id,
                    properties={"correct": payload.get("correct")})

    completed = await bump_daily_tasks(db, learner.id, today, body.event_type, payload)
    for task in completed:
        learner.xp += task.reward_xp
        session.xp_awarded += task.reward_xp

    new_badges = await check_achievements(db, learner)
    await db.flush()
    return {"ok": True, "xp_awarded": xp,
            "daily_tasks_completed": [t.task_key for t in completed],
            "achievements_earned": new_badges, **verdict}


@router.post("/sessions/{session_id}/complete")
async def complete_session(learner_id: UUID, session_id: UUID, body: LessonCompleteIn,
                           actor: ActorDep, db: DbSession) -> dict:
    learner = await learner_for_actor(db, learner_id, actor)
    session = await db.get(LearningSession, session_id)
    if session is None or session.learner_id != learner.id:
        raise not_found("Session not found")
    if session.status != "active":
        raise AppError("session_closed", "This session is already finished")

    hints = int(await db.scalar(
        select(func.count(LearningEvent.id)).where(
            LearningEvent.session_id == session.id,
            LearningEvent.event_type == "hint_used")
    ) or 0)
    stars = stars_for_lesson(body.accuracy, hints)
    xp = session.xp_awarded
    lesson = await db.get(Lesson, session.ref_id) if session.ref_id else None
    if lesson is not None:
        factor = 1.0 if body.accuracy >= 0.8 else 0.75 if body.accuracy >= 0.6 else 0.5
        bonus = round(lesson.xp_reward * factor)
        xp += bonus
        learner.xp += bonus
        # advance the learner's pointer to the next lesson in the module,
        # then the next module's first lesson — the unlock rule, made data.
        nxt = await db.scalar(select(Lesson).where(
            Lesson.module_id == lesson.module_id, Lesson.position > lesson.position
        ).order_by(Lesson.position).limit(1))
        if nxt is None:
            from ..models import Module

            nxt_module = await db.scalar(select(Module).where(
                Module.course_id == lesson.module.course_id,
                Module.position > lesson.module.position).order_by(Module.position).limit(1))
            if nxt_module is not None:
                nxt = await db.scalar(select(Lesson).where(
                    Lesson.module_id == nxt_module.id).order_by(Lesson.position).limit(1))
        if nxt is not None:
            learner.current_lesson_id = nxt.id

    session.status = "completed"
    session.ended_at = datetime.now(timezone.utc)
    session.stars = stars
    session.accuracy = body.accuracy
    session.seconds_spent = body.seconds_spent
    learner.stars += stars
    await track(db, "lesson_completed", learner_id=learner.id,
                properties={"stars": stars, "accuracy": round(body.accuracy, 3),
                            "phonemes": body.phonemes[:12], "xp": xp})
    if lesson is not None:
        await bump_daily_tasks(db, learner.id, datetime.now(timezone.utc).date(),
                               "lesson_completed", {"lesson_id": str(lesson.id)})
    new_achievements = await check_achievements(db, learner)
    await db.flush()
    return {"ok": True, "stars": stars, "xp_awarded": xp,
            "achievements_earned": new_achievements}


@router.post("/sessions/{session_id}/abandon")
async def abandon_session(learner_id: UUID, session_id: UUID,
                         actor: ActorDep, db: DbSession) -> dict:
    learner = await learner_for_actor(db, learner_id, actor)
    session = await db.get(LearningSession, session_id)
    if session is None or session.learner_id != learner.id:
        raise not_found("Session not found")
    if session.status == "active":
        session.status = "abandoned"
        session.ended_at = datetime.now(timezone.utc)
        await track(db, "lesson_abandoned", learner_id=learner.id,
                    properties={"kind": session.kind})
    return {"ok": True}


@router.get("/snapshot", response_model=SnapshotOut)
async def snapshot(learner_id: UUID, actor: ActorDep, db: DbSession) -> SnapshotOut:
    learner = await learner_for_actor(db, learner_id, actor)
    lid = learner.id
    completed = int(await db.scalar(select(func.count(LearningSession.id)).where(
        LearningSession.learner_id == lid, LearningSession.kind == "lesson",
        LearningSession.status == "completed")) or 0)
    q_total = int(await db.scalar(select(func.count(LearningEvent.id)).where(
        LearningEvent.learner_id == lid, LearningEvent.event_type == "question_answered")) or 0)
    q_correct = int(await db.scalar(select(func.count(LearningEvent.id)).where(
        LearningEvent.learner_id == lid, LearningEvent.event_type == "question_answered",
        LearningEvent.payload["correct"].as_boolean() == True)) or 0)  # noqa: E712
    reading = int(await db.scalar(
        select(func.coalesce(func.sum(LearningEvent.payload["minutes"].as_integer()), 0))
        .where(LearningEvent.learner_id == lid,
               LearningEvent.event_type == "reading_practiced")) or 0)
    streak = await db.get(Streak, lid)
    today = datetime.now(timezone.utc).date()
    due = int(await db.scalar(select(func.count(LearnerSkillProgress.id)).where(
        LearnerSkillProgress.learner_id == lid,
        LearnerSkillProgress.due_on <= today)) or 0)
    mastery_rows = list(await db.scalars(select(LearnerSkillProgress).where(
        LearnerSkillProgress.learner_id == lid)))
    return SnapshotOut(
        xp=learner.xp, stars=learner.stars,
        streak_current=streak.current if streak else 0,
        streak_longest=streak.longest if streak else 0,
        lessons_completed=completed, questions_answered=q_total, questions_correct=q_correct,
        reading_minutes=reading, due_reviews=due,
        mastery={r.subject_key: round(r.mastery, 3) for r in mastery_rows},
        current_lesson_id=learner.current_lesson_id,
    )


@router.get("/daily-tasks", response_model=list[DailyTaskOut])
async def daily_tasks(learner_id: UUID, actor: ActorDep, db: DbSession) -> list[DailyTaskOut]:
    learner = await learner_for_actor(db, learner_id, actor)
    tasks = await ensure_daily_tasks(db, learner, datetime.now(timezone.utc).date())
    return [DailyTaskOut(id=t.id, task_key=t.task_key, kind=t.kind, title=t.title,
                         target_count=t.target_count, progress_count=t.progress_count,
                         reward_xp=t.reward_xp, completed=t.completed_at is not None)
            for t in tasks]


@router.get("/mastery", response_model=list[MasteryRowOut])
async def mastery(learner_id: UUID, actor: ActorDep, db: DbSession) -> list[MasteryRowOut]:
    """Per-subject mastery rows — attempts, correct, error_count, box, due day.
    This is what feeds parent dashboards and (later) the adaptive model."""
    learner = await learner_for_actor(db, learner_id, actor)
    rows = list(await db.scalars(
        select(LearnerSkillProgress)
        .where(LearnerSkillProgress.learner_id == learner.id)
        .order_by(LearnerSkillProgress.mastery, LearnerSkillProgress.subject_key)
    ))
    return [MasteryRowOut(
        subject_key=r.subject_key, skill_key=r.skill_key, attempts=r.attempts,
        correct=r.correct, error_count=r.attempts - r.correct,
        mastery=round(r.mastery, 4), srs_box=r.srs_box, due_on=r.due_on,
    ) for r in rows]


@router.get("/recommendation", response_model=RecommendationOut)
async def recommendation(learner_id: UUID, actor: ActorDep, db: DbSession) -> RecommendationOut:
    """Deterministic adaptive rule (see app/progress.next_best_lesson):
    consolidate-if-weak, else next in sequence, with due spaced reviews
    attached. Not random, not client-influenced."""
    learner = await learner_for_actor(db, learner_id, actor)
    rec = await next_best_lesson(db, learner, datetime.now(timezone.utc).date())
    lesson = rec["lesson"]
    return RecommendationOut(
        type=rec["type"], reason=rec["reason"], learner_id=learner.id,
        lesson_id=lesson.id if lesson else None,
        lesson_code=lesson.code if lesson else None,
        lesson_title=lesson.title if lesson else None,
        module_title=rec["module_title"],
        reviews=[ReviewItemOut(subject_key=r.subject_key, srs_box=r.srs_box,
                               mastery=round(r.mastery, 4), due_on=r.due_on)
                 for r in rec["reviews"]],
    )
