"""Pure engine rules — the contract the progress API is built on. Unit level:
fast, deterministic, and the spec a future adaptive layer must keep."""

from datetime import date, timedelta

import pytest

from app.progress import (
    apply_srs,
    bump_streak,
    ensure_daily_tasks,
    stars_for_lesson,
    xp_for_event,
)
from app.analytics import ALLOWED_EVENTS


def test_xp_table():
    assert xp_for_event("lesson_step_completed", {}) == 2
    assert xp_for_event("question_answered", {"correct": True}) == 5
    assert xp_for_event("question_answered", {"correct": False}) == 1
    assert xp_for_event("hint_used", {}) == 0
    assert xp_for_event("game_completed", {"score": 100}) == 5
    assert xp_for_event("game_completed", {"score": 10_000}) == 10  # capped
    assert xp_for_event("pronunciation_practiced", {"score": 61}) == 3
    assert xp_for_event("pronunciation_practiced", {"score": 60.5}) == 3
    assert xp_for_event("pronunciation_practiced", {"score": 59}) == 0
    assert xp_for_event("reading_practiced", {"minutes": 4}) == 4
    assert xp_for_event("reading_practiced", {"minutes": 99}) == 10  # capped
    assert xp_for_event("review_graded", {}) == 2


def test_stars_matrix():
    assert stars_for_lesson(0.95, 0) == 3
    assert stars_for_lesson(0.95, 2) == 2  # hints cap
    assert stars_for_lesson(0.8, 0) == 2
    assert stars_for_lesson(0.5, 0) == 1
    assert stars_for_lesson(0.0, 0) == 0


def test_allowed_events_whitelist_has_product_set():
    for e in ("registration", "assessment_completed", "lesson_started",
              "question_answered", "game_started", "game_completed",
              "daily_task_completed", "ai_tutor_used", "pronunciation_practice",
              "reading_practice", "subscription_started", "subscription_cancelled",
              "feedback_submitted", "onboarding_completed"):
        assert e in ALLOWED_EVENTS
    for leaky in ("password", "location_report", "chat_transcript"):
        assert leaky not in ALLOWED_EVENTS


async def test_streak_states(db):
    from sqlalchemy import select

    from app.models import LearnerProfile, ParentProfile, User
    from app.security import hash_password

    u = User(email="s@t.mail.phonics.dev", password_hash=hash_password("x" * 12))
    db.add(u)
    await db.flush()
    p = ParentProfile(user_id=u.id, display_name="S", locale="en")
    db.add(p)
    await db.flush()
    learner = LearnerProfile(parent_id=p.id, display_name="K")
    db.add(learner)
    await db.flush()

    day = timedelta(days=1)
    d0 = date(2026, 9, 1)
    s, ext, lost = await bump_streak(db, learner, d0)
    assert (s.current, ext, lost) == (1, True, False)
    for i in (1, 2, 3):  # consecutive days grow the streak
        s, ext, lost = await bump_streak(db, learner, d0 + i * day)
        assert (s.current, ext) == (i + 1, True)
    s, ext, lost = await bump_streak(db, learner, d0 + 3 * day)  # same-day repeat
    assert (s.current, ext, lost) == (4, False, False)
    assert s.longest == 4

    s, ext, lost = await bump_streak(db, learner, d0 + 6 * day)  # 2-day gap
    assert (s.current, ext, lost) == (1, False, True) and s.longest == 4

    # a freeze token covers exactly one gap day
    s.freezes = 1
    await db.flush()
    await bump_streak(db, learner, d0 + 6 * day)
    s, ext, _ = await bump_streak(db, learner, d0 + 8 * day)  # 2-day gap w/ freeze
    assert (s.current, ext) == (2, True) and s.freezes == 0
    await db.rollback()


async def test_srs_promote_demote(db):
    from app.models import LearnerProfile, ParentProfile, User
    from app.security import hash_password

    u = User(email="srs@t.test", password_hash=hash_password("x" * 12))
    db.add(u)
    await db.flush()
    p = ParentProfile(user_id=u.id, display_name="S", locale="en")
    db.add(p)
    await db.flush()
    learner = LearnerProfile(parent_id=p.id, display_name="K")
    db.add(learner)
    await db.flush()

    row = await apply_srs(db, learner.id, skill_key="phonics", subject_key="s", correct=True)
    assert row.srs_box == 1 and row.mastery > 0
    m_after_first = row.mastery
    row = await apply_srs(db, learner.id, skill_key="phonics", subject_key="s", correct=True)
    assert row.srs_box == 2
    assert m_after_first < row.mastery < 1.0
    # wrong answer resets box, keeps (decayed) mastery
    before = row.mastery
    row = await apply_srs(db, learner.id, skill_key="phonics", subject_key="s", correct=False)
    assert row.srs_box == 0 and row.mastery < before and row.due_on is not None
    await db.rollback()


async def test_daily_task_shape_is_deterministic(db):
    from datetime import date as _date

    from app.models import LearnerProfile, ParentProfile, User
    from app.security import hash_password

    u = User(email="dt@t.test", password_hash=hash_password("x" * 12))
    db.add(u)
    await db.flush()
    p = ParentProfile(user_id=u.id, display_name="S", locale="en")
    db.add(p)
    await db.flush()
    learner = LearnerProfile(parent_id=p.id, display_name="K")
    db.add(learner)
    await db.flush()

    d = _date(2026, 9, 15)
    tasks = await ensure_daily_tasks(db, learner, d)
    keys = sorted(t.task_key for t in tasks)
    again = await ensure_daily_tasks(db, learner, d)
    assert sorted(t.task_key for t in again) == keys, "must not duplicate on refetch"
    assert any(k.startswith("lesson:") for k in keys)
    assert any(k.startswith("game:") for k in keys)
    assert any(k.startswith("reading:") for k in keys)
    await db.rollback()
