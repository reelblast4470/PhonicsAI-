"""Phase 3: real curriculum content, adaptive recommendation, mastery rows,
assessment banding, and the security invariant that the answer key never
leaves the server before an answer is submitted."""

import json

import pytest

from .conftest import auth, first_lesson_id


async def _parent(client):
    from .conftest import login, register
    email, _ = await register(client)
    tok = (await login(client, email))["access_token"]
    return tok


async def _learner(client, tok, name="Kid"):
    from .conftest import create_learner
    return await create_learner(client, tok, name=name)


# ------------------------------------------------------------ content shape

async def test_full_curriculum_tree_served(client):
    tok = await _parent(client)
    r = await client.get("/api/v1/content/curriculum", headers=auth(tok))
    assert r.status_code == 200
    body = r.json()
    assert body["version"]  # content-version stamp from content_versions
    course = body["courses"][0]
    lessons = [l for m in course["modules"] for l in m["lessons"]]
    assert len(course["modules"]) == 9
    assert len(lessons) >= 50
    steps = [s for l in lessons for s in l["steps"]]
    assert len(steps) == len(lessons) * 10
    questions = [q for s in steps for q in s["questions"]]
    assert len(questions) >= 150
    for l in lessons[:12]:
        types = [s["step_type"] for s in l["steps"]]
        assert types == ["discover", "hear", "see", "understand", "practice",
                        "play", "recall", "speak", "read", "review"]


async def test_curriculum_covers_letters_blends_digraphs_and_cvc(client):
    tok = await _parent(client)
    body = (await client.get("/api/v1/content/curriculum", headers=auth(tok))).json()
    codes = {l["code"] for m in body["courses"][0]["modules"] for l in m["lessons"]}
    import string
    for g in string.ascii_lowercase:
        assert f"letter-{g}" in codes, f"missing letter lesson {g}"
    for d in ("sh", "ch", "th", "wh", "ph"):
        assert f"digraph-{d}" in codes
    assert "skill-blend" in codes and "skill-seg" in codes
    assert any(c.startswith("family-") for c in codes)
    assert any(c.startswith("blends-") for c in codes)
    # CVC content check against the source of truth (20+ words required)
    from app.curriculum import WORDS, word_text
    cvc = [w for w in map(word_text, WORDS)
           if len(w) == 3 and w[1] in "aeiou"]
    assert len(set(cvc)) >= 20


async def test_answer_key_never_leaks(client):
    """Raw payload scan: no serialization path may expose is_correct before
    the learner answers."""
    tok = await _parent(client)
    for path in ("/api/v1/content/courses", "/api/v1/content/curriculum"):
        raw = (await client.get(path, headers=auth(tok))).text
        assert "is_correct" not in raw
    _, lesson_id = await first_lesson_id(client, tok)
    raw = (await client.get(f"/api/v1/content/lessons/{lesson_id}",
                            headers=auth(tok))).text
    assert "is_correct" not in raw


# ------------------------------------------------------------ question engine

async def test_server_grading_returns_verdict_and_explanation(client):
    tok = await _parent(client)
    learner = await _learner(client, tok)
    lid = learner["id"]
    _, lesson_id = await first_lesson_id(client, tok)
    lesson = (await client.get(f"/api/v1/content/lessons/{lesson_id}",
                               headers=auth(tok))).json()
    practice = next(s for s in lesson["steps"] if s["step_type"] == "practice")
    q = practice["questions"][0]
    sid = (await client.post(f"/api/v1/learners/{lid}/sessions",
                             json={"kind": "lesson", "ref_id": lesson_id},
                             headers=auth(tok))).json()["id"]
    # deliberately answer WRONG (first choice — the server knows better)
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "question_answered",
        "payload": {"question_id": q["id"], "answer_id": q["answers"][0]["id"],
                    "phoneme": lesson["steps"][2]["payload"]["grapheme"]},
    }, headers=auth(tok))
    assert r.status_code == 200
    verdict = r.json()
    assert verdict["correct"] in (True, False)
    assert verdict["correct_answer_id"]  # revealed only after answering
    if not verdict["correct"]:
        assert verdict["chosen_feedback"] or verdict["explanation"]
    # and the revealed key matches what the DB holds
    from app.db import get_session_factory
    from app.models import Answer
    from sqlalchemy import select
    async with get_session_factory()() as db:
        row = await db.scalar(select(Answer.id).where(
            Answer.id == verdict["correct_answer_id"], Answer.is_correct.is_(True)))
        assert row is not None


async def test_replay_returns_verdict_without_double_award(client):
    tok = await _parent(client)
    learner = await _learner(client, tok)
    lid = learner["id"]
    _, lesson_id = await first_lesson_id(client, tok)
    lesson = (await client.get(f"/api/v1/content/lessons/{lesson_id}",
                               headers=auth(tok))).json()
    q = lesson["steps"][4]["questions"][0]
    sid = (await client.post(f"/api/v1/learners/{lid}/sessions",
                             json={"kind": "lesson", "ref_id": lesson_id},
                             headers=auth(tok))).json()["id"]
    body = {"event_type": "question_answered",
            "payload": {"question_id": q["id"], "answer_id": q["answers"][0]["id"],
                        "phoneme": "s"},
            "client_event_id": "p3-replay-0001"}
    first = (await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events",
                               json=body, headers=auth(tok))).json()
    again = (await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events",
                               json=body, headers=auth(tok))).json()
    assert again["duplicate"] is True
    assert again["xp_awarded"] == first["xp_awarded"]
    assert again["correct"] == first["correct"]


# ------------------------------------------------------------ mastery + SRS

async def test_mastery_rows_track_errors_deterministically(client):
    tok = await _parent(client)
    learner = await _learner(client, tok)
    lid = learner["id"]
    _, lesson_id = await first_lesson_id(client, tok)
    lesson = (await client.get(f"/api/v1/content/lessons/{lesson_id}",
                               headers=auth(tok))).json()
    q = lesson["steps"][1]["questions"][0]  # the /s/ hear question
    sid = (await client.post(f"/api/v1/learners/{lid}/sessions",
                             json={"kind": "lesson", "ref_id": lesson_id},
                             headers=auth(tok))).json()["id"]

    async def answer(payload_extra: dict | None = None):
        return (await client.post(
            f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
                "event_type": "question_answered",
                "payload": {"question_id": q["id"],
                            "answer_id": payload_extra["answer_id"],
                            "phoneme": "s", **(payload_extra.get("x") or {})},
            }, headers=auth(tok))).json()

    # Two different options: exactly one is correct (server decides which).
    a1 = q["answers"][0]
    a2 = q["answers"][1]
    v1 = await answer({"answer_id": a1["id"]})
    v2 = await answer({"answer_id": a2["id"]})
    assert (v1["correct"], v2["correct"]) in ((False, True), (True, False))

    rows = (await client.get(f"/api/v1/learners/{lid}/mastery",
                             headers=auth(tok))).json()
    srow = next(r for r in rows if r["subject_key"] == "s")
    assert srow["attempts"] == 2 and srow["correct"] == 1 and srow["error_count"] == 1
    if v1["correct"] is False:   # wrong → right: box resets then promotes to 1
        assert srow["srs_box"] == 1
        assert abs(srow["mastery"] - 0.15) < 1e-6
    else:                        # right → wrong: box falls back to 0
        assert srow["srs_box"] == 0
        assert abs(srow["mastery"] - 0.105) < 1e-6  # 0.15 − 30% of it


async def test_other_parents_cannot_read_mastery(client):
    tok_a = await _parent(client)
    learner = await _learner(client, tok_a)
    tok_b = await _parent(client)
    r = await client.get(f"/api/v1/learners/{learner['id']}/mastery",
                         headers=auth(tok_b))
    assert r.status_code == 404  # not visible, not merely forbidden


# ------------------------------------------------------------ recommendation

async def test_recommendation_sequence_consolidate_and_advance(client):
    tok = await _parent(client)
    learner = await _learner(client, tok)
    lid = learner["id"]

    rec = (await client.get(f"/api/v1/learners/{lid}/recommendation",
                            headers=auth(tok))).json()
    assert rec["type"] == "lesson"
    assert rec["lesson_code"] == "letter-s"
    assert rec["reason"] == "next in sequence"

    # complete with weak accuracy → the SAME lesson repeats (consolidate)
    lesson_id = rec["lesson_id"]
    sid = (await client.post(f"/api/v1/learners/{lid}/sessions",
                             json={"kind": "lesson", "ref_id": lesson_id},
                             headers=auth(tok))).json()["id"]
    await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/complete", json={
        "stars": 1, "accuracy": 0.3, "seconds_spent": 120, "phonemes": ["s"],
    }, headers=auth(tok))
    rec2 = (await client.get(f"/api/v1/learners/{lid}/recommendation",
                             headers=auth(tok))).json()
    assert rec2["lesson_code"] == "letter-s"
    assert rec2["reason"] == "consolidate"

    # redo it properly → advance to letter-a (module order, deterministic)
    sid = (await client.post(f"/api/v1/learners/{lid}/sessions",
                             json={"kind": "lesson", "ref_id": lesson_id},
                             headers=auth(tok))).json()["id"]
    await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/complete", json={
        "stars": 3, "accuracy": 0.95, "seconds_spent": 150, "phonemes": ["s"],
    }, headers=auth(tok))
    rec3 = (await client.get(f"/api/v1/learners/{lid}/recommendation",
                             headers=auth(tok))).json()
    assert rec3["lesson_code"] == "letter-a"
    assert rec3["reason"] == "next in sequence"


async def test_recommendation_starts_at_placement_band(client, db):
    """A placed 'beginning' reader skips the letter modules → word families."""
    tok = await _parent(client)
    learner = await _learner(client, tok)
    lid = learner["id"]
    items = (await client.get("/api/v1/assessments", headers=auth(tok))).json()
    started = (await client.post(
        f"/api/v1/learners/{lid}/assessments/{items[0]['key']}/start",
        headers=auth(tok))).json()
    # answer everything the *wrong* way except enough to land 'beginning'
    answers = []
    for i, q in enumerate(started["questions"]):
        pick = q["answers"][0] if i < 13 else q["answers"][-1]
        answers.append({"question_id": q["id"], "answer_id": pick["id"]})
    # we can't know which are right; use the server verdict pattern instead:
    res = (await client.post(
        f"/api/v1/learners/{lid}/assessments/results/{started['result_id']}/submit",
        json={"answers": answers}, headers=auth(tok))).json()
    assert res["score_max"] == 16  # 16 real items now, not the 8-item dev stub
    assert res["band_key"] in {"pre-reader", "emerging", "beginning",
                              "progressing", "proficient"}
    # the submitted band was persisted server-side, not just returned
    after = (await client.get(f"/api/v1/learners/{lid}", headers=auth(tok))).json()
    assert after["reading_level_key"] == res["band_key"]

    # placement floor: force a known band (levels are server-set by design —
    # not client-patchable), then expect the module floor to apply
    from app.models import LearnerProfile
    prof = await db.get(LearnerProfile, learner["id"])
    prof.reading_level_key = "beginning"
    await db.commit()

    rec = (await client.get(f"/api/v1/learners/{lid}/recommendation",
                            headers=auth(tok))).json()
    assert rec["lesson_code"] == "family-at"  # module 6 floor for 'beginning'


# ------------------------------------------------------------ persistence

async def test_progress_persists_in_database(client, db):
    """The claim parents care about: after the flow, the DATABASE (not just
    the response) shows the lesson completed, XP earned and a mastery row."""
    from app.models import LearningSession, LearnerSkillProgress, LearnerProfile
    from sqlalchemy import select

    tok = await _parent(client)
    learner = await _learner(client, tok)
    lid = learner["id"]
    _, lesson_id = await first_lesson_id(client, tok)
    sid = (await client.post(f"/api/v1/learners/{lid}/sessions",
                             json={"kind": "lesson", "ref_id": lesson_id},
                             headers=auth(tok))).json()["id"]
    await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "review_graded", "payload": {"phoneme": "s", "grade": 5},
    }, headers=auth(tok))
    await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/complete", json={
        "stars": 2, "accuracy": 0.7, "seconds_spent": 180, "phonemes": ["s"],
    }, headers=auth(tok))

    row = await db.get(LearnerProfile, learner["id"])
    assert row.xp > 0 and row.stars >= 2
    sess = await db.scalar(select(LearningSession).where(
        LearningSession.id == sid))
    assert sess.status == "completed"
    assert sess.accuracy is not None
    sp = await db.scalar(select(LearnerSkillProgress).where(
        LearnerSkillProgress.learner_id == learner["id"],
        LearnerSkillProgress.subject_key == "s"))
    assert sp is not None and sp.correct >= 1
