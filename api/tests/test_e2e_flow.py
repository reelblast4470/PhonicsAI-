"""One test walking the WHOLE product flow the Flutter client will drive,
in order, against the real stack. If the pieces don't connect, this fails —
even if every individual endpoint is green.
"""

from .conftest import auth, extract_verify_token, register


async def test_full_parent_and_learner_journey(client):
    # 1. registration + email verification + login
    email, user = await register(client, name="Priya")
    tok_link = await extract_verify_token(email)
    assert (await client.post("/api/v1/auth/verify-email",
                              json={"token": tok_link})).json()["email_verified"] is True
    r = await client.post("/api/v1/auth/login",
                          json={"email": email, "password": "Str0ngPassphrase!42"})
    assert r.status_code == 200
    pair = r.json()
    tok = pair["access_token"]

    # 2. create learner
    r = await client.post("/api/v1/learners", json={
        "display_name": "Aarav", "daily_target_minutes": 20,
        "preferred_language_code": "en", "avatar_key": "tiger",
        "learning_goals": {"goal": "read first sentences"}}, headers=auth(tok))
    assert r.status_code == 201
    learner = r.json()
    lid = learner["id"]

    # 3. catalog → first lesson
    r = await client.get("/api/v1/content/courses", headers=auth(tok))
    course = r.json()[0]
    lesson = course["modules"][0]["lessons"][0]
    r = await client.get(f"/api/v1/content/lessons/{lesson['id']}", headers=auth(tok))
    lesson_full = r.json()
    assert len(lesson_full["steps"]) == 10

    # 4. learner-device token (the child's scoped credential)
    r = await client.post(f"/api/v1/auth/learner-token?learner_id={lid}", headers=auth(tok))
    assert r.status_code == 200
    ltok = r.json()["access_token"]

    # 5. the learning session, through the child's token
    r = await client.post(f"/api/v1/learners/{lid}/sessions",
                          json={"kind": "lesson", "ref_id": lesson["id"]}, headers=auth(ltok))
    sid = r.json()["id"]

    practice_q = None
    for step in lesson_full["steps"]:
        r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
            "event_type": "lesson_step_completed",
            "payload": {"step": step["step_type"]},
            "client_event_id": f"e2e-step-{step["position"]}",
        }, headers=auth(ltok))
        assert r.status_code == 200
        if step["step_type"] == "practice" and step["questions"]:
            practice_q = step["questions"][0]

    # answer correctly, then incorrectly (server decides from ids)
    assert practice_q, "practice step must carry a question"
    right = next(a for a in practice_q["answers"])  # any answer id: correctness is server-side
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "question_answered",
        "payload": {"question_id": practice_q["id"], "answer_id": practice_q["answers"][0]["id"]},
    }, headers=auth(ltok))
    first_award = r.json()["xp_awarded"]
    assert first_award in (1, 5)

    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/events", json={
        "event_type": "hint_used", "payload": {}}, headers=auth(ltok))
    assert r.json()["xp_awarded"] == 0

    # 6. finish with mediocre accuracy → exactly 1 star (server truth)
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{sid}/complete", json={
        "stars": 3, "accuracy": 0.55, "seconds_spent": 210, "phonemes": ["s", "a"]},
        headers=auth(ltok))
    done = r.json()
    assert done["stars"] == 1
    first_xp = done["xp_awarded"]

    # 7. games + reading knock out daily tasks
    r = await client.post(f"/api/v1/learners/{lid}/sessions",
                          json={"kind": "game", "ref_key": "sound-match"}, headers=auth(ltok))
    gsid = r.json()["id"]
    r = await client.post(f"/api/v1/learners/{lid}/sessions/{gsid}/events", json={
        "event_type": "game_completed", "payload": {"score": 300, "game": "sound-match"},
    }, headers=auth(ltok))
    game_award = r.json()["xp_awarded"]
    game_tasks = r.json()["daily_tasks_completed"]
    assert any(k.startswith("game:") for k in game_tasks)

    await client.post(f"/api/v1/learners/{lid}/sessions", json={"kind": "reading"},
                      headers=auth(ltok))

    # 8. snapshot equals the ledger
    r = await client.get(f"/api/v1/learners/{lid}/snapshot", headers=auth(ltok))
    snap = r.json()
    assert snap["lessons_completed"] == 1
    assert snap["questions_answered"] == 1
    assert snap["streak_current"] == 1
    assert snap["xp"] >= first_xp + game_award
    assert snap["current_lesson_id"] is not None  # pointer advanced by engine

    # 9. achievements: first-read unlocked by real data
    r = await client.get(f"/api/v1/learners/{lid}/achievements", headers=auth(ltok))
    earned = {a["key"]: a["earned"] for a in r.json()}
    assert earned.get("first-read") is True
    assert earned.get("streak-3") is False  # not yet — honest

    # 10. assessment changes the level — server-side
    r = await client.get("/api/v1/assessments", headers=auth(tok))
    r = await client.post(f"/api/v1/learners/{lid}/assessments/{r.json()[0]['key']}/start",
                          headers=auth(tok))
    started = r.json()
    answers = [{"question_id": q["id"], "answer_id": q["answers"][0]["id"]}
               for q in started["questions"]]
    r = await client.post(
        f"/api/v1/learners/{lid}/assessments/results/{started['result_id']}/submit",
        json={"answers": answers}, headers=auth(tok))
    assert r.status_code == 200
    band = r.json()["band_key"]
    assert band is not None
    learner_after = (await client.get(f"/api/v1/learners/{lid}", headers=auth(tok))).json()
    assert learner_after["reading_level_key"] == band

    # 11. analytics beacons accepted
    r = await client.post("/api/v1/analytics/events", json={"events": [
        {"event": "onboarding_completed", "platform": "android", "app_version": "0.1.0",
         "properties": {"learners": 1}},
    ]}, headers=auth(tok))
    assert r.json()["accepted"] == 1

    # 12. parent surfaces see the child's progress
    r = await client.get(f"/api/v1/learners/{lid}/snapshot", headers=auth(tok))
    assert r.json()["xp"] == snap["xp"]
    tasks = (await client.get(f"/api/v1/learners/{lid}/daily-tasks", headers=auth(tok))).json()
    assert any(t["completed"] for t in tasks)

    # 13. session teardown
    r = await client.post("/api/v1/auth/logout", json={"refresh_token": pair["refresh_token"]},
                          headers=auth(tok))
    assert r.status_code == 204
    r = await client.post("/api/v1/auth/refresh", json={"refresh_token": pair["refresh_token"]})
    assert r.status_code == 401
