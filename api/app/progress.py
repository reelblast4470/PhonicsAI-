"""The progress engine.

Everything a learner earns is *derived* from the append-only learning_events
ledger — no route "adds XP" ad hoc. Rules live here, are pure, and are unit
tested directly. This is also the seam where an adaptive model plugs in later:
it reads the same ledger and would write `next_best_lesson` suggestions; no
schema change is needed.

Award table (v1 — intentionally simple and explainable to a parent):
    lesson step completed        +2 xp
    question correct             +5 xp        wrong answer +1 (effort) and no star change
    hint used                    +0 xp (logged; lowers the lesson star cap)
    game round completed         +min(10, round(score/20))
    pronunciation practiced       +3 xp when score >= 60
    reading practiced             +1 xp per minute, capped 10 per event
    sound review (SRS graded)     +2 xp
    lesson completed             xp_reward scaled: x1.0 acc>=0.8, x0.75 acc>=0.6, x0.5 else
    daily task completed         that task's reward_xp

Stars for a lesson: accuracy >=0.9 -> 3, >=0.7 -> 2, > 0 -> 1 (hints cap at 2).

SRS (per skill+subject, Leitner 0..4): intervals 1/2/4/8/16 days; correct
promotes, wrong resets to box 0 due tomorrow. Mastery moves fractionally:
    correct: m += (1-m)*0.15     wrong: m -= m*0.30
Deterministic — same inputs, same history, same numbers, everywhere.
"""

from datetime import date, datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import (
    Achievement,
    Course,
    DailyTask,
    LearningEvent,
    LearningSession,
    LearnerAchievement,
    LearnerProfile,
    LearnerSkillProgress,
    Lesson,
    Module,
    Streak,
)

SRS_INTERVALS = (1, 2, 4, 8, 16)


def xp_for_event(event_type: str, payload: dict) -> int:
    match event_type:
        case "lesson_step_completed":
            return 2
        case "question_answered":
            return 5 if payload.get("correct") else 1
        case "answer_wrong":
            return 1
        case "hint_used":
            return 0
        case "game_completed":
            return min(10, max(1, round(int(payload.get("score", 0)) / 20)))
        case "pronunciation_practiced":
            return 3 if float(payload.get("score", 0)) >= 60 else 0
        case "reading_practiced":
            return min(10, max(0, int(payload.get("minutes", 0))))
        case "review_graded":
            return 2
        case _:
            return 0


def stars_for_lesson(accuracy: float, hints_used: int) -> int:
    stars = 3 if accuracy >= 0.9 else 2 if accuracy >= 0.7 else 1 if accuracy > 0 else 0
    if hints_used > 0:
        stars = min(stars, 2)
    return stars


def _today(payload: dict) -> date:
    raw = payload.get("activity_date")
    if isinstance(raw, str):
        try:
            return date.fromisoformat(raw)
        except ValueError:
            pass
    return datetime.now(timezone.utc).date()


async def get_or_create_streak(db: AsyncSession, learner_id: UUID) -> Streak:
    streak = await db.get(Streak, learner_id)
    if streak is None:
        streak = Streak(learner_id=learner_id, current=0, longest=0)
        db.add(streak)
        await db.flush()
    return streak


async def bump_streak(db: AsyncSession, learner: LearnerProfile, on: date) -> tuple[Streak, bool, bool]:
    """Returns (streak, extended, lost). Same-day repeats are no-ops."""
    streak = await get_or_create_streak(db, learner.id)
    last = streak.last_active_date
    extended = lost = False
    if last is None:
        streak.current = 1
        extended = True
    elif on == last:
        pass
    elif (on - last).days == 1:
        streak.current += 1
        extended = True
    elif (on - last).days > 1:
        if streak.freezes > 0:
            streak.freezes -= 1
            # burn one gap day per freeze; recheck distance after burn
            if (on - last).days == 2:
                streak.current += 1
                extended = True
            else:
                lost = streak.current >= 3
                streak.current = 1
        else:
            lost = streak.current >= 3
            streak.current = 1
    streak.longest = max(streak.longest, streak.current)
    streak.last_active_date = on
    return streak, extended, lost


async def apply_srs(
    db: AsyncSession,
    learner_id: UUID,
    *,
    skill_key: str,
    subject_key: str,
    correct: bool,
) -> LearnerSkillProgress:
    row = await db.scalar(
        select(LearnerSkillProgress).where(
            LearnerSkillProgress.learner_id == learner_id,
            LearnerSkillProgress.skill_key == skill_key,
            LearnerSkillProgress.subject_key == subject_key,
        )
    )
    if row is None:
        row = LearnerSkillProgress(
            learner_id=learner_id, skill_key=skill_key, subject_key=subject_key
        )
        db.add(row)
        await db.flush()
    row.attempts += 1
    if correct:
        row.correct += 1
        row.mastery = min(1.0, row.mastery + (1 - row.mastery) * 0.15)
        row.srs_box = min(4, row.srs_box + 1)
        row.due_on = _today({}) + timedelta(days=SRS_INTERVALS[row.srs_box])
    else:
        row.mastery = max(0.0, row.mastery - row.mastery * 0.30)
        row.srs_box = 0
        row.due_on = _today({}) + timedelta(days=1)
    return row


async def ensure_daily_tasks(
    db: AsyncSession, learner: LearnerProfile, on: date
) -> list[DailyTask]:
    existing = list(
        await db.scalars(
            select(DailyTask).where(
                DailyTask.learner_id == learner.id, DailyTask.task_date == on
            )
        )
    )
    if existing:
        return existing

    tasks: list[DailyTask] = []
    # 1) the current (or next) lesson
    lesson = await db.get(Lesson, learner.current_lesson_id) if learner.current_lesson_id else None
    if lesson is None:
        module_id = await db.scalar(
            select(Module.id)
            .join(Course, Course.id == Module.course_id)
            .where(Course.status == "published")
            .order_by(Module.position)
            .limit(1)
        )
        if module_id:
            lesson = await db.scalar(
                select(Lesson).where(Lesson.module_id == module_id).order_by(Lesson.position).limit(1)
            )
    if lesson:
        tasks.append(
            DailyTask(
                learner_id=learner.id, task_date=on, task_key=f"lesson:{lesson.id}",
                kind="lesson", title=f"Finish “{lesson.title}”", target_count=1,
                reward_xp=15,
            )
        )
    # 2) a game — deterministic rotation off the date
    from .seed_data import GAME_KEYS  # small constant list lives with the catalog

    game = GAME_KEYS[on.toordinal() % len(GAME_KEYS)]
    tasks.append(
        DailyTask(
            learner_id=learner.id, task_date=on, task_key=f"game:{game}",
            kind="game", title="Play a game to lock in the sounds", target_count=1,
            reward_xp=10,
        )
    )
    # 3) due sound reviews, if any
    due = await db.scalar(
        select(func.count(LearnerSkillProgress.id)).where(
            LearnerSkillProgress.learner_id == learner.id,
            LearnerSkillProgress.due_on <= on,
        )
    )
    if (due or 0) > 0:
        n = min(6, int(due))
        tasks.append(
            DailyTask(
                learner_id=learner.id, task_date=on, task_key="review:due",
                kind="review", title=f"Review {n} tricky sounds", target_count=n,
                reward_xp=10,
            )
        )
    # 4) free reading
    tasks.append(
        DailyTask(
            learner_id=learner.id, task_date=on, task_key="reading:any",
            kind="reading", title=f"Read together for {max(5, learner.daily_target_minutes - 5)} minutes",
            target_count=1, reward_xp=5,
        )
    )
    db.add_all(tasks)
    await db.flush()
    return tasks


async def bump_daily_tasks(
    db: AsyncSession, learner_id: UUID, on: date, event_type: str, payload: dict
) -> list[DailyTask]:
    """Map one learning event onto today's tasks; award completion rewards."""
    from .analytics import track

    completed: list[DailyTask] = []
    tasks = list(
        await db.scalars(
            select(DailyTask).where(
                DailyTask.learner_id == learner_id,
                DailyTask.task_date == on,
                DailyTask.completed_at.is_(None),
            )
        )
    )
    for t in tasks:
        hit = 0
        if event_type == "lesson_completed" and t.kind == "lesson" and t.task_key.endswith(str(payload.get("lesson_id", ""))):
            hit = 1
        elif event_type == "game_completed" and t.kind == "game":
            hit = 1
        elif event_type == "review_graded" and t.kind == "review":
            hit = 1
        elif event_type == "reading_practiced" and t.kind == "reading":
            hit = max(1, int(payload.get("minutes", 0)) // 5)
        if not hit:
            continue
        t.progress_count = min(t.target_count, t.progress_count + hit)
        if t.progress_count >= t.target_count:
            t.completed_at = datetime.now(timezone.utc)
            completed.append(t)
    if completed:
        await track(db, "daily_task_completed", learner_id=learner_id,
                    properties={"count": len(completed), "date": on.isoformat()})
    return completed


METRIC_QUERIES = {
    "lessons_completed": lambda lid: select(func.count(LearningSession.id)).where(
        LearningSession.learner_id == lid,
        LearningSession.kind == "lesson",
        LearningSession.status == "completed",
    ),
    "games_completed": lambda lid: select(func.count(LearningSession.id)).where(
        LearningSession.learner_id == lid,
        LearningSession.kind == "game",
        LearningSession.status == "completed",
    ),
    "stars_total": lambda lid: select(func.coalesce(func.sum(LearningSession.stars), 0)).where(
        LearningSession.learner_id == lid
    ),
    "questions_correct": lambda lid: select(func.count(LearningEvent.id)).where(
        LearningEvent.learner_id == lid,
        LearningEvent.event_type == "question_answered",
        LearningEvent.payload["correct"].as_boolean() == True,  # noqa: E712
    ),
}


async def check_achievements(db: AsyncSession, learner: LearnerProfile) -> list[str]:
    """Evaluate the (few, simple) achievement rules after events. Returns newly
    earned keys. O(#achievements) queries, tiny table, fine at scale; replace
    with a worker reading the ledger when the rule set grows."""
    earned_rows = list(
        await db.scalars(select(LearnerAchievement.achievement_id).where(
            LearnerAchievement.learner_id == learner.id
        ))
    )
    earned_ids = set(earned_rows)
    new_keys: list[str] = []
    for ach in await db.scalars(select(Achievement)):
        if ach.id in earned_ids:
            continue
        crit = ach.criteria or {}
        metric = crit.get("metric")
        gte = int(crit.get("gte", 1))
        if metric == "xp_total":
            value = learner.xp
        elif metric == "streak_current":
            s = await db.get(Streak, learner.id)
            value = s.current if s else 0
        elif metric in METRIC_QUERIES:
            value = int(await db.scalar(METRIC_QUERIES[metric](learner.id)) or 0)
        else:
            continue
        if value >= gte:
            db.add(LearnerAchievement(learner_id=learner.id, achievement_id=ach.id))
            new_keys.append(ach.key)
    return new_keys
