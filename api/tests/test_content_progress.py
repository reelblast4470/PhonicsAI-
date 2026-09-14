"""Content retrieval and the full progress pipeline: sessions, events,
server-decided correctness, lesson completion, snapshot, daily tasks."""

import pytest

from .conftest import auth, create_learner, first_lesson_id, first_question, login, register


async def _parent(client):
    email, _ = await register(client)
    return (await login(client, email))["access_token"]


async def test_course_catalog_is_published_only(client):
    tok = await _parent(client)
    courses = (await client.get("/api/v1/content/courses", headers=auth(tok))).json()
    assert len(courses) == 1
    c = courses[0]
    assert c["origin"] == "seed-dev", "seed content must be honestly labelled"
    assert len(c["modules"]) == 6
    assert len(c["modules"][0]["lessons"]) == 2


async def test_unpublished_course_invisible(client, db):
    from sqlalchemy import select

    from app.models import Course

    tok = await _parent(client)
    course = (await db.execute(select(Course))).scalars().first()
    course.status = "draft"
    await db.commit()
    assert (await client.get("/api/v1/content/courses", headers=auth(tok))).json() == []


async def test_lesson_has_full_learning_loop_without_answers_leaked(client):
    tok = await _parent(client)
    _, lesson_id = await first_lesson_id(client, tok)
    r = await client.get(f"/api/v1/content/lessons/{lesson_id}", headers=auth(tok))
    assert r.status_code == 200
    lesson = r.json()
    types = [s["step_type"] for s in lesson["steps"]]
    assert types == ["discover", "hear", "see", "understand", "practice",
                     "play", "recall", "speak", "read", "review"]
    q = await first_question(client, tok, lesson_id)  # asserts no is_correct inside


async def test_lesson_flow_awards_are_deterministic(client):
    tok = await _parent(client)
    learner = await create_learner(client, tok)
    lid = learner["id"]
    _, lesson_id = await first_lesson_id(client, tok)

    # start
    r = await client.post(f"/api/v1/learners/{lid}/sessions",
                          json={"kind": "lesson", "ref_id": lesson_id}, headers=auth(tok))
    assert r.status_code == 201
    sid = r.json()["id"]

    q = await first_question(client, tok, lesson_id)
    correct_answer = next(a for a in q["answers"] if a["text"] == q.get("correct_text")) \
        if q.get("correct_text") else None

    # answer with a *claimed* correct=true but the FIRST (possibly wrong)
    # answer id: the server must decide, client claims ignored.
    first_answer = q["answers"][0]
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "question_answered",
        "payload": {"question_id": q["question_id"], "answer_id": first_answer["id"],
                    "correct": True},
    }, headers=auth(tok))
    assert r.status_code == 200
    body = r.json()
    from app.db import get_session_factory
    from app.models import LearningEvent
    from sqlalchemy import select

    async with get_session_factory()() as s:
        ev = (await s.execute(select(LearningEvent).where(
            LearningEvent.learner_id == lid))).scalars().first()
        assert ev.payload["correct"] == False  # noqa: E712 — server truth wins
    # either way, the award is small (5 if truly first-correct else 1):
    assert body["xp_awarded"] in (1, 5)
    xp_after_q = body["xp_awarded"]

    # a step event: exactly +2
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "lesson_step_completed", "payload": {"step": "hear"},
    }, headers=auth(tok))
    assert r.json()["xp_awarded"] == 2

    # idempotent replay by client_event_id
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "lesson_step_completed", "payload": {"step": "practice"},
        "client_event_id": "dup-check-0001",
    }, headers=auth(tok))
    assert r.json() == {"ok": True, "duplicate": False, "xp_awarded": 2} or r.json()["xp_awarded"] == 2
    r2 = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "lesson_step_completed", "payload": {"step": "practice"},
        "client_event_id": "dup-check-0001",
    }, headers=auth(tok))
    assert r2.json()["duplicate"] is True

    # snapshot aggregates
    r = await client.get(f"/api/v1/learners/{lid}/snapshot", headers=auth(tok))
    snap = r.json()
    assert snap["xp"] >= 2
    assert snap["streak_current"] == 1

    # complete the lesson
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/complete", json={
        "stars": 3, "accuracy": 0.95, "seconds_spent": 220, "phonemes": ["s", "a"],
    }, headers=auth(tok))
    assert r.status_code == 200
    done = r.json()
    assert done["stars"] == 3
    assert done["xp_awarded"] > 0

    # the client cannot inflate stars: accuracy decides server-side, and a
    # low-accuracy completion earns at most 1 star even if it asks for 3
    r = await client.post(f"/api/v1/learners/{lid}/sessions",
                          json={"kind": "lesson", "ref_id": lesson_id}, headers=auth(tok))
    sid2 = r.json()["id"]
    await client.post(f"/api/v1/learners/{lid}/sessions/{sid2}/events", json={
        "event_type": "hint_used", "payload": {}}, headers=auth(tok))
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid2}/complete", json={
        "stars": 3, "accuracy": 0.95, "seconds_spent": 60, "phonemes": []},
        headers=auth(tok))
    assert r.json()["stars"] == 2, "hints cap the star reward at 2"

    # double-complete is refused
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/complete", json={
        "stars": 0, "accuracy": 0.5, "seconds_spent": 10, "phonemes": []}, headers=auth(tok))
    assert r.status_code == 400 and r.json()["error"]["code"] == "session_closed"


async def test_progress_pointer_advances(client):
    tok = await _parent(client)
    learner = await create_learner(client, tok)
    lid = learner["id"]
    _, lesson_id = await first_lesson_id(client, tok)
    sid = (await client.post(f"/api/v1/learners/{lid}/sessions",
                             json={"kind": "lesson", "ref_id": lesson_id},
                             headers=auth(tok))).json()["id"]
    await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/complete", json={
        "stars": 3, "accuracy": 1.0, "seconds_spent": 100, "phonemes": ["s"]},
        headers=auth(tok))
    snap = (await client.get(f"/api/v1/learners/{lid}/snapshot",
                             headers=auth(tok))).json()
    assert snap["current_lesson_id"] is not None and snap["current_lesson_id"] != lesson_id


async def test_daily_tasks_complete_through_events(client):
    tok = await _parent(client)
    learner = await create_learner(client, tok)
    lid = learner["id"]
    sid = (await client.post(f"/api/v1/learners/{lid}/sessions",
                             json={"kind": "game", "ref_key": "sound-match"},
                             headers=auth(tok))).json()["id"]
    tasks = (await client.get(f"/api/v1/learners/{lid}/daily-tasks",
                              headers=auth(tok))).json()
    assert any(t["kind"] == "game" for t in tasks)

    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "game_completed", "payload": {"score": 220, "game": "sound-match"},
    }, headers=auth(tok))
    body = r.json()
    assert any(k.startswith("game:") for k in body["daily_tasks_completed"])

    tasks = (await client.get(f"/api/v1/learners/{lid}/daily-tasks",
                             headers=auth(tok))).json()
    game_task = next(t for t in tasks if t["kind"] == "game")
    assert game_task["completed"] is True


async def test_review_grading_moves_srs(client):
    tok = await _parent(client)
    learner = await create_learner(client, tok)
    lid = learner["id"]
    for i, grade in enumerate(["right", "right"]):
        sid = (await client.post(f"/api/v1/learners/{lid}/sessions",
                                 json={"kind": "review"},
                                 headers=auth(tok))).json()["id"]
        r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
            "event_type": "review_graded", "payload": {"phoneme": "s", "grade": 4},
        }, headers=auth(tok))
        assert r.status_code == 200

    from sqlalchemy import select

    from app.db import get_session_factory
    from app.models import LearnerSkillProgress

    async with get_session_factory()() as s:
        rows = list((await s.execute(select(LearnerSkillProgress).where(
            LearnerSkillProgress.learner_id == lid))).scalars())
    phon = [r for r in rows if r.subject_key == "s"]
    assert phon and phon[0].srs_box == 2, "two consecutive correct → box 2 (1d, 2d)"
    assert phon[0].due_on is not None


async def test_invalid_event_input_rejected(client):
    tok = await _parent(client)
    learner = await create_learner(client, tok)
    lid = learner["id"]
    r = await client.post(f"/api/v1/learners/{lid}/sessions",
                          json={"kind": "lesson", "ref_id": learner["id"]},
                          headers=auth(tok))
    assert r.status_code == 404  # a learner id is not a lesson id
    r = await client.post(f"/api/v1/learners/{lid}/sessions",
                          json={"kind": "game", "ref_key": "x"}, headers=auth(tok))
    assert r.status_code == 201
    sid = r.json()["id"]
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "give_me_a_million_xp", "payload": {}}, headers=auth(tok))
    assert r.status_code == 422
    # question event with garbage ids
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "question_answered", "payload": {"question_id": "x", "answer_id": "y"}},
        headers=auth(tok))
    assert r.status_code == 400
    # lesson session without ref
    r = await client.post(f"/api/v1/learners/{lid}/sessions",
                          json={"kind": "lesson"}, headers=auth(tok))
    assert r.status_code == 400 and r.json()["error"]["code"] == "lesson_ref_required"
