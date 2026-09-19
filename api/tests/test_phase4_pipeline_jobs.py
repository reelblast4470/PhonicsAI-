"""Phase 4 — pipeline behaviour: job state machine, cross-source conflict
reports, verbatim/copyright guard, failure → retry, proposal state
enforcement, audit rows, and the copilot.

The seeded curriculum ships with `phonics_foundations`; the paste fixtures
below use sentences the rule-extractor recognises. Everything runs on the
mock provider (cost 0) — the *flow* is what's under test.
"""

from sqlalchemy import select

from .conftest import admin_token, auth


TEXT_SH = ('The digraph "sh" makes the /ʃ/ sound, as in ship and shop and fish. '
           "When you teach blending, always model it first: c a t, then cat. "
           "The child must recall the sound, not the rule. "
           + "Padding sentences so the chunk has realistic length. " * 3)

SUPPORT_TEXT = ("Use picture mnemonics to lock in each letter sound, because "
                "young children remember images longer than rules. " * 3)


async def _paste(client, tok, text=TEXT_SH, **meta):
    body = {"title": meta.pop("title", "Phonics Notes"),
            "license_type": meta.pop("license", "public_domain"),
            "category": "phonics", **meta, "text": text}
    r = await client.post("/api/v1/admin/content/sources/paste",
                          json=body, headers=auth(tok))
    assert r.status_code == 201, r.text
    return r.json()


async def _process(client, tok, source_id) -> dict:
    r = await client.post(f"/api/v1/admin/content/sources/{source_id}/process",
                          headers=auth(tok))
    assert r.status_code == 200, r.text
    return r.json()


# ------------------------------------------------------------- job states
async def test_job_transitions_to_completed_or_needs_review(client):
    tok = await admin_token(client)
    src = await _paste(client, tok)
    out = await _process(client, tok, src["id"])
    assert out["status"] in ("completed", "needs_review")
    jobs = (await client.get(f"/api/v1/admin/content/jobs?source_id={src['id']}",
                             headers=auth(tok))).json()
    job = jobs[0]
    assert job["status"] == out["status"]
    assert job["attempts"] == 1
    assert job["stats"]["chunks"] >= 1


async def test_run_completed_job_is_refused(client):
    tok = await admin_token(client)
    src = await _paste(client, tok)
    out = await _process(client, tok, src["id"])
    jobs = (await client.get(f"/api/v1/admin/content/jobs?source_id={src['id']}",
                             headers=auth(tok))).json()
    r = await client.post(f"/api/v1/admin/content/jobs/{jobs[0]['id']}/run",
                          headers=auth(tok))
    if out["status"] == "completed":
        assert r.status_code == 409, r.text   # finished jobs don't silently re-run
        assert r.json()["error"]["code"] == "already_finished"
    else:  # needs_review: re-running is the documented recovery path
        assert r.status_code == 200, r.text


async def test_run_twice_in_parallel_only_claims_once(client):
    """The atomic status flip is the single runner guarantee."""
    import asyncio
    tok = await admin_token(client)
    src = await _paste(client, tok)
    jobs = (await client.get(f"/api/v1/admin/content/jobs?source_id={src['id']}",
                             headers=auth(tok))).json()
    job_id = jobs[0]["id"]
    r1, r2 = await asyncio.gather(
        client.post(f"/api/v1/admin/content/jobs/{job_id}/run", headers=auth(tok)),
        client.post(f"/api/v1/admin/content/jobs/{job_id}/run", headers=auth(tok)))
    codes = sorted([r1.status_code, r2.status_code])
    assert codes == [200, 409], (r1.text, r2.text)
    loser = r2 if r2.status_code == 409 else r1
    assert loser.json()["error"]["code"] == "job_busy"


# ---------------------------------------------------------------- conflict
async def test_cross_source_conflict_flagged_not_resolved(client):
    tok = await admin_token(client)
    a = await _paste(client, tok, text=(TEXT_SH), title="Modern Phonics")
    await _process(client, tok, a["id"])
    b = await _paste(client, tok, text=(
        'The digraph "sh" makes the /s/ sound in all positions, like in ship and shop. '
        + SUPPORT_TEXT), title="Old Primer")
    out_b = await _process(client, tok, b["id"])
    assert out_b["status"] == "needs_review"
    conflicts = (await client.get("/api/v1/admin/content/conflicts",
                                  headers=auth(tok))).json()
    assert len(conflicts) == 1
    c = conflicts[0]
    assert "sh" in c["topic"]
    assert c["status"] == "open"
    # the AI must not have picked a side: the conflicted knowledge produced
    # no proposal targeting the sh lesson
    props = (await client.get("/api/v1/admin/content/proposals?source_id="
                              + b["id"], headers=auth(tok))).json()
    for p in props:
        d = (await client.get(f"/api/v1/admin/content/proposals/{p['id']}",
                              headers=auth(tok))).json()
        assert d["target_code"] != "digraph-sh"
    # resolving is a human-only PATCH
    r = await client.patch(f"/api/v1/admin/content/conflicts/{c['id']}",
                           json={"status": "resolved",
                                 "notes": "keep /ʃ/ — the modern source is right"},
                           headers=auth(tok))
    assert r.status_code == 200
    again = (await client.get("/api/v1/admin/content/conflicts?status=open",
                              headers=auth(tok))).json()
    assert again == []


# ------------------------------------------------------------- verbatim guard
async def test_verbatim_copy_into_a_draft_is_blocked(client):
    """>= verbatim_max_words consecutive words of a source chunk inside a
    draft blocks approval — the copyright guard is enforced, not decorative."""
    tok = await admin_token(client)
    src = await _paste(client, tok)   # TEXT_SH: a known extractable document
    await _process(client, tok, src["id"])
    props = (await client.get("/api/v1/admin/content/proposals?source_id="
                              + src["id"], headers=auth(tok))).json()
    assert props, "no proposals to guard for this source"
    pid = props[0]["id"]
    quoted = ('The digraph "sh" makes the /ʃ/ sound, as in ship and shop and '
              "fish. When you teach blending, always model it first: c a t, then "
              "cat. The child must recall the sound, not the rule. Padding "
              "sentences so the chunk has realistic length.")
    r = await client.patch(f"/api/v1/admin/content/proposals/{pid}",
                           json={"payload": {"lesson": {"title": "Copycat lesson",
                                                         "summary": quoted},
                                              "new_questions": []}},
                           headers=auth(tok))
    assert r.status_code == 200, r.text
    detail = (await client.get(f"/api/v1/admin/content/proposals/{pid}",
                               headers=auth(tok))).json()
    flags = {f["code"] for f in (detail["validation"] or {}).get("flags", [])}
    assert "verbatim_reproduction" in flags
    assert detail["validation"]["passed"] is False
    # and a blocked proposal cannot be force-approved through the happy path
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/approve",
                          json={"notes": "looks fine"}, headers=auth(tok))
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "validation_failed"


# ------------------------------------------------------------- failure/retry
async def test_failed_provider_call_marks_job_failed_then_retry_recovers(client, monkeypatch):
    tok = await admin_token(client)
    src = await _paste(client, tok)
    from app.ingestion import pipeline as pl
    import app.ingestion.ai as ai_mod
    real = ai_mod._build

    class Boom(ai_mod.MockAIService):
        async def extract_knowledge(self, chunk_text, context):
            raise ai_mod.AiError("ai_unavailable", "provider exploded mid-analysis")

    ai_mod._build = lambda: Boom()
    ai_mod.reset_ai_service()
    try:
        r = await client.post(f"/api/v1/admin/content/sources/{src['id']}/process",
                              headers=auth(tok))
        assert r.status_code == 200
        assert r.json()["status"] == "failed"
        assert "provider exploded" in r.json()["error"]
        jobs = (await client.get(f"/api/v1/admin/content/jobs?source_id={src['id']}",
                                 headers=auth(tok))).json()
        assert jobs[0]["status"] == "failed"
        # usage telemetry recorded the error
        usage = (await client.get("/api/v1/admin/content/usage", headers=auth(tok))).json()
        assert usage["totals"]["errors"] >= 1
        # retry → queued → run on the healthy provider → completes
        rid = jobs[0]["id"]
        r = await client.post(f"/api/v1/admin/content/jobs/{rid}/retry", headers=auth(tok))
        assert r.status_code == 200 and r.json()["status"] == "queued"
    finally:
        ai_mod._build = real
        ai_mod.reset_ai_service()
    r = await client.post(f"/api/v1/admin/content/jobs/{rid}/run", headers=auth(tok))
    assert r.status_code == 200
    body = r.json()
    assert body["status"] in ("completed", "needs_review")
    stats = body["stats"]
    assert stats["knowledge_new"] >= 2 or stats["chunks"] == 0


# --------------------------------------------------- proposal state machine
async def test_proposal_status_machine_gates_approve(client):
    """draft→ai_reviewed→human_review→approved→published is enforced by the
    API: approve requires a reviewed status; publish requires approved."""
    tok = await admin_token(client)
    src = await _paste(client, tok)
    await _process(client, tok, src["id"])
    props = (await client.get("/api/v1/admin/content/proposals", headers=auth(tok))).json()
    props = [p for p in props if p["source_id"] == src["id"]]
    assert props, "pipeline should have drafted at least one proposal"
    pid = props[0]["id"]
    # publish directly from ai_reviewed/human_review → refused
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/publish",
                          json={"notes": "yolo"}, headers=auth(tok))
    assert r.status_code == 409
    # approve → then publish guard passes status-wise (target may be missing
    # for new_lesson drafts; we only assert the status machine here)
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/approve",
                          json={"notes": "looked at evidence"}, headers=auth(tok))
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "approved"
    # approving twice → refused (not in reviewable state anymore)
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/approve",
                          json={}, headers=auth(tok))
    assert r.status_code == 409
    # reject a second proposal from the approved-published path
    if len(props) > 1:
        pid2 = props[1]["id"]
        r = await client.post(f"/api/v1/admin/content/proposals/{pid2}/reject",
                              json={"notes": "not useful"}, headers=auth(tok))
        assert r.status_code == 200 and r.json()["status"] == "rejected"
        r = await client.post(f"/api/v1/admin/content/proposals/{pid2}/approve",
                              json={}, headers=auth(tok))
        assert r.status_code == 409  # rejected proposals stay rejected


async def test_admin_audit_records_pipeline_actions(client):
    tok = await admin_token(client)
    src = await _paste(client, tok)
    await _process(client, tok, src["id"])
    from app.db import get_session_factory
    from app.models import AdminAuditLog
    async with get_session_factory()() as db:
        rows = list(await db.scalars(select(AdminAuditLog).where(
            AdminAuditLog.action.in_(("content.source_paste", "content.source_process")))))
    assert {r.action for r in rows} == {"content.source_paste", "content.source_process"}
    for r in rows:
        assert r.admin_id is not None


# ---------------------------------------------------------------- copilot
async def test_copilot_missing_concepts_and_questions(client):
    tok = await admin_token(client)
    src = await _paste(client, tok, text=SUPPORT_TEXT)
    await _process(client, tok, src["id"])

    r = await client.post("/api/v1/admin/content/copilot",
                          json={"prompt": "find missing phonics concepts in our curriculum"},
                          headers=auth(tok))
    assert r.status_code == 200, r.text
    body = r.json()
    assert "missing" in body["report"]
    # the seeded curriculum genuinely lacks silent-e / long vowels
    assert "silent-e" in body["report"]["missing"] or "long-vowels" in body["report"]["missing"]

    before = len((await client.get("/api/v1/admin/content/proposals",
                                   headers=auth(tok))).json())
    r = await client.post("/api/v1/admin/content/copilot",
                          json={"prompt": "create 6 practice questions for blending"},
                          headers=auth(tok))
    assert r.status_code == 200
    body = r.json()
    assert body["report"]["count"] >= 1
    assert len(body["proposals"]) == 1
    after = len((await client.get("/api/v1/admin/content/proposals",
                                  headers=auth(tok))).json())
    assert after == before + 1  # drafted as proposals, never published

    # the drafted proposal has deterministic single-key answers
    pid = body["proposals"][0]
    d = (await client.get(f"/api/v1/admin/content/proposals/{pid}",
                          headers=auth(tok))).json()
    for q in d["payload"]["new_questions"]:
        keys = [a for a in q["answers"] if a["is_correct"]]
        assert len(keys) == 1, "question without exactly one correct answer"


async def test_copilot_unknown_command_replies_with_help(client):
    tok = await admin_token(client)
    r = await client.post("/api/v1/admin/content/copilot",
                          json={"prompt": "tell me a joke about vowels"},
                          headers=auth(tok))
    assert r.status_code == 200
    assert "missing" in r.json()["reply"].lower() or "commands" in r.json()["reply"].lower()
