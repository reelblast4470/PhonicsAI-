"""Phase 5 — the three seams closed: server-verified receipts, the AI tutor
endpoint (with quota + safety + SSE), and the support intake queue.

Real Postgres through the real HTTP layer; the "stores" are exercised in
mock mode (deterministic) while the real-provider config paths are asserted
as honest 503s rather than faked successes.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from .conftest import admin_token, auth, create_learner, login, register

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

RECEIPT = {"store": "mock", "product_id": "plus_monthly",
           "purchase_token": "mock-token-phase5-0001"}


async def _parent(client):
    email, _ = await register(client)
    pair = await login(client, email)
    return pair["access_token"]


async def _verify(client, token, body=None):
    return await client.post("/api/v1/subscriptions/me/receipt",
                             json=body or RECEIPT, headers=auth(token))


# --------------------------------------------------------------------------
# receipt verification
# --------------------------------------------------------------------------

async def test_client_report_grants_nothing(client, parent_client):
    c, tok, _ = parent_client
    r = await c.post("/api/v1/subscriptions/me/events",
                     json={"event": "started", "plan_key": "plus_monthly",
                           "store_receipt": "whatever-the-device-says"},
                     headers=auth(tok))
    assert r.status_code == 202 and r.json()["entitlement_changed"] is False
    me = (await c.get("/api/v1/subscriptions/me", headers=auth(tok))).json()
    assert me["verified"] is False and me["status"] == "free"


async def test_verified_receipt_grants_plus(client):
    tok = await _parent(client)
    r = await _verify(client, tok)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["granted"] is True and body["verified"] is True
    assert body["plan_key"] == "plus_monthly" and body["status"] == "active"
    assert body["current_period_end"] is not None
    me = (await client.get("/api/v1/subscriptions/me", headers=auth(tok))).json()
    assert me["verified"] is True


async def test_reverify_is_idempotent(client):
    tok = await _parent(client)
    assert (await _verify(client, tok)).status_code == 200
    again = (await _verify(client, tok)).json()
    assert again["already_recorded"] is True and again["granted"] is True


async def test_receipt_replay_across_accounts_blocked(client):
    tok_a, tok_b = await _parent(client), await _parent(client)
    assert (await _verify(client, tok_a)).status_code == 200
    r = await _verify(client, tok_b)          # same store transaction, new mom
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "receipt_used_elsewhere"
    me = (await client.get("/api/v1/subscriptions/me", headers=auth(tok_b))).json()
    assert me["status"] == "free" and me["verified"] is False


async def test_failed_and_unknown_receipts_rejected(client):
    tok = await _parent(client)
    r = await _verify(client, tok, {**RECEIPT, "purchase_token": "mock-token-fail-9999"})
    assert r.status_code == 400 and r.json()["error"]["code"] == "receipt_invalid"
    r = await _verify(client, tok, {**RECEIPT, "product_id": "platinum_nonsense"})
    assert r.status_code == 400 and r.json()["error"]["code"] == "unknown_product"


async def test_lifetime_receipt_has_no_expiry(client):
    tok = await _parent(client)
    r = await _verify(client, tok, {**RECEIPT, "product_id": "plus_lifetime",
                                    "purchase_token": "mock-token-lifetime-77"})
    assert r.status_code == 200 and r.json()["current_period_end"] is None


async def test_store_product_id_also_maps(client):
    tok = await _parent(client)
    r = await _verify(client, tok, {**RECEIPT,
                                    "product_id": "com.phonicsai.plus.yearly",
                                    "purchase_token": "mock-token-storeprod-5"})
    assert r.status_code == 200 and r.json()["plan_key"] == "plus_yearly"


async def test_verifier_modes_are_honest(monkeypatch):
    from app import billing
    from app.errors import AppError

    class S:
        billing_mode = "off"
        is_production = False
        google_access_token = ""
        google_package = ""
        appstore_shared_secret = ""
    monkeypatch.setattr(billing, "get_settings", lambda: S())
    with pytest.raises(AppError) as e:
        await billing.verify_receipt(store="mock", product_id="plus_monthly",
                                     token="abcdefghij")
    assert e.value.code == "billing_disabled"

    class G(S):
        billing_mode = "google_play"
    monkeypatch.setattr(billing, "get_settings", lambda: G())
    with pytest.raises(AppError) as e:          # app-store token vs play mode
        await billing.verify_receipt(store="app_store", product_id="plus_monthly",
                                     token="abcdefghij")
    assert e.value.code == "store_mismatch"
    with pytest.raises(AppError) as e:          # play mode without ops config
        await billing.verify_receipt(store="google_play", product_id="plus_monthly",
                                     token="abcdefghij")
    assert e.value.code == "billing_not_configured"


def test_production_refuses_mock_billing():
    from app.config import Settings
    s = Settings(_env_file=None, environment="production",
                 jwt_secret="z" * 48,
                 database_url="postgresql+asyncpg://prod:s3cret@db.internal:5432/phonicsai")
    with pytest.raises(RuntimeError, match="BILLING_MODE"):
        s.validate_for_boot()


# --------------------------------------------------------------------------
# tutor
# --------------------------------------------------------------------------

async def _tutor_ctx(client, tok):
    learner = await create_learner(client, tok, name="Aria")
    return learner["id"]


async def test_tutor_plain_json_and_exchange_recorded(client):
    tok = await _parent(client)
    lid = await _tutor_ctx(client, tok)
    r = await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                          json={"message": "how do I blend?"}, headers=auth(tok))
    assert r.status_code == 200, r.text
    body = r.json()
    assert "Blending" in body["text"] and body["flagged"] is False
    assert isinstance(body["chips"], list)
    ex = (await client.get(f"/api/v1/learners/{lid}/tutor/exchanges",
                           headers=auth(tok))).json()["exchanges"]
    assert len(ex) == 1 and ex[0]["question"] == "how do I blend?"
    assert ex[0]["flagged"] is False


async def test_tutor_sse_stream_shape(client):
    tok = await _parent(client)
    lid = await _tutor_ctx(client, tok)
    r = await client.post(f"/api/v1/learners/{lid}/tutor/reply",
                          json={"message": "what does \"sh\" say?"}, headers=auth(tok))
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/event-stream")
    chunks = [line[6:] for line in r.text.splitlines() if line.startswith("data: ")]
    assert len(chunks) >= 2                      # >=1 token chunk + final
    import json as _json
    final = _json.loads(chunks[-1])
    assert final["chips"] and "sh" in final["text"].lower()
    # tokens reassemble into exactly the final text
    joined = "".join(_json.loads(c)["text"] for c in chunks[:-1])
    assert joined == final["text"]


async def test_tutor_off_topic_is_flagged_not_punished(client):
    tok = await _parent(client)
    lid = await _tutor_ctx(client, tok)
    r = await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                          json={"message": "give me a game cheat code"},
                          headers=auth(tok))
    body = r.json()
    assert body["flagged"] is True and "only chat about sounds" in body["text"]
    ex = (await client.get(f"/api/v1/learners/{lid}/tutor/exchanges",
                           headers=auth(tok))).json()["exchanges"]
    assert ex[0]["flagged"] is True               # kept for the parent report


async def test_tutor_free_quota_then_plus_unlocks(client):
    tok = await _parent(client)
    lid = await _tutor_ctx(client, tok)
    for i in range(3):
        r = await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                              json={"message": f"hello {i}"}, headers=auth(tok))
        assert r.status_code == 200
    r = await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                          json={"message": "hello once more"}, headers=auth(tok))
    assert r.status_code == 429
    assert r.json()["error"]["code"] == "tutor_quota_exceeded"
    # a server-verified receipt lifts it (not a client event report)
    await client.post("/api/v1/subscriptions/me/events",
                      json={"event": "started", "plan_key": "plus_yearly"},
                      headers=auth(tok))
    r = await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                          json={"message": "hello still blocked"}, headers=auth(tok))
    assert r.status_code == 429
    assert (await _verify(client, tok, {**RECEIPT,
                                        "purchase_token": "mock-token-quota-x"})).status_code == 200
    r = await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                          json={"message": "now unblocked"}, headers=auth(tok))
    assert r.status_code == 200, r.text


async def test_tutor_chat_disabled_and_privacy(client):
    tok = await _parent(client)
    lid = await _tutor_ctx(client, tok)
    r = await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                          json={"message": "hello", "open_chat_allowed": False},
                          headers=auth(tok))
    assert r.status_code == 403
    assert r.json()["error"]["code"] == "tutor_chat_disabled"
    # starters keep working (scripted chips are the point when chat is off)
    r = await client.get(f"/api/v1/learners/{lid}/tutor/starters", headers=auth(tok))
    assert r.status_code == 200 and isinstance(r.json()["starters"], list)


async def test_tutor_foreign_learner_unreachable(client):
    tok_a, tok_b = await _parent(client), await _parent(client)
    lid = await _tutor_ctx(client, tok_a)
    r = await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                          json={"message": "hello?"}, headers=auth(tok_b))
    assert r.status_code == 404                  # 404, never 403: no probing


async def test_tutor_starters_use_struggling_sounds(client, db_read):
    from app.models import LearnerSkillProgress
    tok = await _parent(client)
    lid = await _tutor_ctx(client, tok)
    db = db_read
    db.add(LearnerSkillProgress(learner_id=uuid.UUID(lid), skill_key="phonics",
                               subject_key="th", mastery=0.2, attempts=6, correct=1))
    await db.commit()
    starters = (await client.get(f"/api/v1/learners/{lid}/tutor/starters",
                                 headers=auth(tok))).json()["starters"]
    assert any("th" in s for s in starters)
    r = await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                          json={"message": "what should we do"}, headers=auth(tok))
    assert "th" in r.json()["text"] or "th" in " ".join(r.json()["chips"])


async def test_admin_tutor_review_view(client):
    tok = await _parent(client)
    lid = await _tutor_ctx(client, tok)
    await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                      json={"message": "what is my phone number?"}, headers=auth(tok))
    await client.post(f"/api/v1/learners/{lid}/tutor/reply?sse=false",
                      json={"message": "hello"}, headers=auth(tok))
    at = await admin_token(client)
    rows = (await client.get("/api/v1/admin/tutor/exchanges?flagged_only=true",
                             headers=auth(at))).json()["exchanges"]
    assert len(rows) == 1 and rows[0]["learner"] == "Aria"
    everything = (await client.get("/api/v1/admin/tutor/exchanges",
                                   headers=auth(at))).json()["exchanges"]
    assert len(everything) == 2
    # learner token can never hit the admin view
    assert (await client.get("/api/v1/admin/tutor/exchanges",
                             headers=auth(tok))).status_code == 401


# --------------------------------------------------------------------------
# support
# --------------------------------------------------------------------------

async def test_support_ticket_full_loop(client):
    tok = await _parent(client)
    r = await client.post("/api/v1/support/tickets", json={
        "subject": "App closes during reading time",
        "body": "Since the last update the app quits when my child opens the "
                "reader on our tablet (Android).",
        "locale": "en", "app_version": "1.4.2", "platform": "android"},
        headers=auth(tok))
    assert r.status_code == 201, r.text
    tid = r.json()["id"]
    assert r.json()["status"] == "open"

    at = await admin_token(client)
    q = (await client.get("/api/v1/admin/support/tickets?status=open",
                          headers=auth(at))).json()["tickets"]
    assert len(q) == 1 and q[0]["body"]                      # admins read the real text
    r = await client.patch(f"/api/v1/admin/support/tickets/{tid}",
                           json={"status": "in_progress"}, headers=auth(at))
    assert r.status_code == 200 and r.json()["status"] == "in_progress"
    r = await client.patch(f"/api/v1/admin/support/tickets/{tid}",
                           json={"status": "resolved",
                                 "admin_reply": "Thanks — fixed in 1.4.3, out today."},
                           headers=auth(at))
    assert r.status_code == 200 and r.json()["answered_at"]

    mine = (await client.get(f"/api/v1/support/tickets/{tid}", headers=auth(tok))).json()
    assert mine["admin_reply"] == "Thanks — fixed in 1.4.3, out today."
    notes = (await client.get("/api/v1/notifications", headers=auth(tok))).json()
    assert any(n["kind"] == "support_reply" for n in notes)
    # audit trail recorded the reply
    rows = (await client.get("/api/v1/admin/audit-logs?limit=50",
                             headers=auth(at))).json()
    assert any(e["action"] == "support.update" for e in rows)


async def test_support_ticket_validation_and_isolation(client):
    tok = await _parent(client)
    r = await client.post("/api/v1/support/tickets",
                          json={"subject": "hi", "body": "too short", "locale": "en"},
                          headers=auth(tok))
    assert r.status_code == 422                               # subject min 3? 'hi' is 2
    r = await client.post("/api/v1/support/tickets",
                          json={"subject": "ok subject", "body": "x" * 5,
                                "locale": "en"}, headers=auth(tok))
    assert r.status_code == 422                               # body min 10

    other = await _parent(client)
    lst = (await client.get("/api/v1/support/tickets", headers=auth(other))).json()
    assert lst["tickets"] == []
    tid = (await client.post("/api/v1/support/tickets",
                             json={"subject": "mine", "body": "y" * 20,
                                   "locale": "en"}, headers=auth(tok))).json()["id"]
    assert (await client.get(f"/api/v1/support/tickets/{tid}",
                             headers=auth(other))).status_code == 404


async def test_support_role_answers_tickets(client, db):
    from app.models import AdminUser
    from app.security import create_access_token, hash_password
    su = AdminUser(username="support-phase5",
                   password_hash=hash_password("Support-55!phase"),
                   display_name="Support", role="support")
    db.add(su)
    await db.commit()                                          # visible to request sessions
    token, _ = create_access_token(su.id, "admin", minutes=30)
    h = {"Authorization": f"Bearer {token}"}

    tok = await _parent(client)
    tid = (await client.post("/api/v1/support/tickets",
                             json={"subject": "billing question",
                                   "body": "Where do I cancel Plus?",
                                   "locale": "en"}, headers=auth(tok))).json()["id"]
    # support role CAN act in its own domain (unlike content writes)
    r = await client.patch(f"/api/v1/admin/support/tickets/{tid}",
                           json={"status": "resolved",
                                 "admin_reply": "Play Store → Payments → Subscriptions."},
                           headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "resolved"
    # and it still cannot touch the content domain
    assert (await client.post("/api/v1/admin/content/sources/paste",
                              json={"title": "nope", "license_type": "public_domain",
                                    "text": "t" * 300}, headers=h)).status_code == 403
