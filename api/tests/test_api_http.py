"""HTTP behaviour: status codes, error shapes, rate limiting, security
headers, analytics ingestion, subscriptions, assessment scoring."""

import pytest

from .conftest import admin_token, auth, create_learner, login, register


async def test_structured_errors_and_headers(client):
    tok = None
    r = await client.get("/api/v1/learners/00000000-0000-0000-0000-000000000000/snapshot")
    assert r.status_code == 401
    body = r.json()
    assert body["error"]["code"] == "unauthorized"
    assert "message" in body["error"]
    # security headers present on every response
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["x-frame-options"] == "DENY"
    assert r.headers["referrer-policy"] == "no-referrer"
    assert r.headers["cache-control"] == "no-store"


async def test_validation_errors_are_machine_readable(client):
    email, _ = await register(client)
    tok = (await login(client, email))["access_token"]
    r = await client.post("/api/v1/learners", json={"display_name": ""}, headers=auth(tok))
    assert r.status_code == 422
    det = r.json()["error"]["details"][0]
    assert det["field"] == "display_name"


async def test_unhandled_errors_are_masked(app):
    import httpx as _httpx

    def boom():
        raise ValueError("SECRET_DB_CONN=postgres://user:hunter12@host")

    app.add_api_route("/api/v1/__boom", boom)
    transport = _httpx.ASGITransport(app=app, raise_app_exceptions=False)
    async with _httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        r = await c.get("/api/v1/__boom")
    assert r.status_code == 500
    text = r.text
    assert r.status_code == 500
    assert "hunter12" not in text and "SECRET" not in text
    assert r.json()["error"]["code"] == "internal_error"


async def test_rate_limit_enforces_on_login(client, app):
    from app.limiter import limiter

    limiter.enabled = True
    limiter.reset()
    try:
        for i in range(8):
            r = await client.post("/api/v1/auth/login", json={
                "email": f"nobody{i}@mail.phonics.dev", "password": "whatever1234!"})
            if r.status_code == 429:
                break
        else:
            pytest.fail("login never hit the rate limit")
        assert r.status_code == 429
        body = r.json()
        assert "detail" in body or "error" in body
    finally:
        limiter.enabled = False
        limiter.reset()


async def test_analytics_batch_whitelist_and_ownership(client):
    email, _ = await register(client)
    tok = (await login(client, email))["access_token"]
    learner = await create_learner(client, tok)
    other_email, _ = await register(client)
    other = await create_learner(client, (await login(client, other_email))["access_token"])

    r = await client.post("/api/v1/analytics/events", json={"events": [
        {"event": "onboarding_completed", "learner_id": learner["id"]},
        {"event": "lesson_started", "learner_id": str(other["id"]),
         "properties": {"why": "foreign learner — must be dropped silently"}},
        {"event": "collect_free_chat_logs_please"},
    ]}, headers=auth(tok))
    assert r.status_code == 200
    body = r.json()
    assert body["accepted"] == 2 and body["rejected"] == 1

    from sqlalchemy import select

    from app.db import get_session_factory
    from app.models import AnalyticsEvent

    async with get_session_factory()() as s:
        rows = list((await s.execute(select(AnalyticsEvent).where(
            AnalyticsEvent.event.in_(["onboarding_completed", "lesson_started",
                                      "collect_free_chat_logs_please"])))).scalars())
    assert len(rows) == 2
    foreign = [e for e in rows if e.event == "lesson_started"]
    assert foreign[0].learner_id is None, "cross-family learner ids dropped"


async def test_client_billing_report_cannot_grant_entitlement(client):
    email, _ = await register(client)
    tok = (await login(client, email))["access_token"]
    r = await client.get("/api/v1/subscriptions/me", headers=auth(tok))
    assert r.json()["status"] == "free"

    r = await client.post("/api/v1/subscriptions/me/events", json={
        "event": "started", "plan_key": "plus_yearly", "store_receipt": "fake-receipt"},
        headers=auth(tok))
    assert r.status_code == 202
    assert r.json()["entitlement_changed"] is False

    sub = (await client.get("/api/v1/subscriptions/me", headers=auth(tok))).json()
    assert sub["status"] == "free", "client-reported receipts must not flip anything"


async def test_admin_publish_grant_and_audit(client):
    atok = await admin_token(client)
    email, user = await register(client)
    assert (await client.get("/api/v1/subscriptions/me",
                             headers=auth((await login(client, email))["access_token"]))
            ).json()["status"] == "free"

    r = await client.post(
        f"/api/v1/admin/subscriptions/{user['id']}/grant?plan_key=plus_yearly&months=12",
        headers=auth(atok))
    assert r.status_code == 200
    parent_tok = (await login(client, email))["access_token"]
    assert (await client.get("/api/v1/subscriptions/me",
                             headers=auth(parent_tok))).json()["status"] == "active"

    r = await client.get("/api/v1/admin/audit-logs", headers=auth(atok))
    assert r.status_code == 200
    assert any("subscription.grant" == row["action"] for row in r.json())


async def test_assessment_scoring_and_level_assignment(client):
    email, _ = await register(client)
    tok = (await login(client, email))["access_token"]
    learner = await create_learner(client, tok)
    lid = learner["id"]

    r = await client.get("/api/v1/assessments", headers=auth(tok))
    assert r.json()[0]["key"] == "placement-english-v2"

    r = await client.post(f"/api/v1/learners/{lid}/assessments/placement-english-v2/start",
                          headers=auth(tok))
    assert r.status_code == 200
    started = r.json()
    qs = started["questions"]
    assert len(qs) == 16
    assert all("is_correct" not in a for q in qs for a in q["answers"])

    # resolve the key from the DB: answering all correctly must land the top
    # band — proving banding + level assignment are computed server-side.
    from app.db import get_session_factory
    from app.models import Answer
    from sqlalchemy import select
    async with get_session_factory()() as s:
        right = {str(a.question_id): str(a.id) for a in await s.scalars(
            select(Answer).where(Answer.is_correct.is_(True),
                                 Answer.question_id.in_([q["id"] for q in qs])))}
    answers = [{"question_id": q["id"], "answer_id": right[q["id"]]} for q in qs]
    r = await client.post(f"/api/v1/learners/{lid}/assessments/results/{started['result_id']}/submit",
                          json={"answers": answers}, headers=auth(tok))
    assert r.status_code == 200
    res = r.json()
    assert res["score_max"] == 16 and res["score"] == 16
    assert res["band_key"] == "proficient"

    learner_after = (await client.get(f"/api/v1/learners/{lid}", headers=auth(tok))).json()
    assert learner_after["reading_level_key"] == res["band_key"]

    # double submit refused
    r = await client.post(f"/api/v1/learners/{lid}/assessments/results/{started['result_id']}/submit",
                          json={"answers": answers}, headers=auth(tok))
    assert r.status_code == 400 and r.json()["error"]["code"] == "already_submitted"


async def test_feedback_round_trip(client):
    email, _ = await register(client)
    tok = (await login(client, email))["access_token"]
    r = await client.post("/api/v1/feedback", json={
        "category": "idea", "message": "Please add Welsh-language lessons soon, thanks!"},
        headers=auth(tok))
    assert r.status_code == 201
    fb = r.json()
    assert fb["status"] == "new"

    r = await client.get("/api/v1/feedback", headers=auth(tok))
    assert len(r.json()) == 1

    atok = await admin_token(client)
    r = await client.patch(f"/api/v1/admin/feedback/{fb['id']}?status=in_progress",
                           headers=auth(atok))
    assert r.status_code == 200
    assert (await client.get("/api/v1/feedback", headers=auth(tok))).json()[0]["status"] \
        == "in_progress"


async def test_healthz(client):
    r = await client.get("/healthz")
    assert r.status_code == 200 and r.json()["status"] == "ok"
