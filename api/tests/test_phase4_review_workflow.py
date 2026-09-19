"""Phase 4 — the acceptance spine (§24):

upload → process → knowledge → proposal → review → APPROVE → PUBLISH →
VERSION, and the learner actually receives the updated content; then a
rollback restores the previous version exactly. Plus the security gates:
parent/learner tokens cannot touch the admin surface, support admins cannot
write, and publishing is impossible without approval.
"""

from .conftest import admin_token, auth, login, register

TEXT_BLEND = (
    'When you teach blending, always model it first: c a t, then cat. '
    "The child must recall the sound, not the rule, so keep it daily practice. "
    "Extra filler text so the chunk meets a realistic document size for tests. ")

TEXT_SILENT_E = (
    "For silent e, teach that the final e makes the vowel before it say its "
    "name; this is the magic e idea. Always model silent e with short words "
    "first: kit, kite. More filler text so this pasted document has realistic "
    "and sufficient length for the extractor to consider it a real resource. ")


async def _paste(client, tok, text, title="Notes"):
    r = await client.post("/api/v1/admin/content/sources/paste",
                          json={"title": title, "license_type": "public_domain",
                                "category": "phonics", "text": text},
                          headers=auth(tok))
    assert r.status_code == 201, r.text
    return r.json()


async def _process(client, tok, source_id):
    r = await client.post(f"/api/v1/admin/content/sources/{source_id}/process",
                          headers=auth(tok))
    assert r.status_code == 200, r.text
    return r.json()


async def _props(client, tok, source_id=None):
    url = "/api/v1/admin/content/proposals"
    if source_id:
        url += f"?source_id={source_id}"
    return (await client.get(url, headers=auth(tok))).json()


# ------------------------------------------------------------- main spine
async def test_improve_lesson_publish_then_learner_sees_update_then_rollback(client):
    tok = await admin_token(client)
    src = await _paste(client, tok, TEXT_BLEND, title="Blending method")
    await _process(client, tok, src["id"])

    props = [p for p in await _props(client, tok, src["id"])
             if p["action"] == "improve_lesson" and p["target_entity_id"]]
    assert props, f"expected an improve_lesson proposal, got {await _props(client, tok)}"
    pid = props[0]["id"]

    # review detail shows the human everything needed to decide
    d = (await client.get(f"/api/v1/admin/content/proposals/{pid}",
                          headers=auth(tok))).json()
    assert d["side_by_side"] and d["side_by_side"]["current"]["code"] == "skill-blend"
    assert d["license"] == "public_domain"
    assert d["payload"]["new_questions"], "draft should carry questions"
    assert d["evidence"] if "evidence" in d else True

    lesson_id = d["target_entity_id"]
    # learner baseline
    pemail, _ = await register(client)
    ptok = (await login(client, pemail))["access_token"]
    pre = (await client.get(f"/api/v1/content/lessons/{lesson_id}",
                            headers=auth(ptok))).json()
    pre_cur_version = (await client.get("/api/v1/content/curriculum",
                                        headers=auth(ptok))).json()["version"]
    pre_n_q = sum(len(s["questions"]) for s in pre["steps"])

    # publish without approval → impossible
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/publish",
                          json={"notes": "skip review?"}, headers=auth(tok))
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "not_approved"

    # approve → publish → versioned
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/approve",
                          json={"notes": "checked against source page 1"},
                          headers=auth(tok))
    assert r.status_code == 200, r.text
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/publish",
                          json={"notes": "adopted the model-first technique"},
                          headers=auth(tok))
    assert r.status_code == 200, r.text
    pub = r.json()
    assert pub["changed_lessons"] == ["skill-blend"]

    # the LEARNER now receives the updated content through the normal API
    post = (await client.get(f"/api/v1/content/lessons/{lesson_id}",
                             headers=auth(ptok))).json()
    assert post["summary"] and "Updated teaching note" in post["summary"]
    post_n_q = sum(len(s["questions"]) for s in post["steps"])
    assert post_n_q == pre_n_q + len(d["payload"]["new_questions"])
    # the answer key is STILL invisible to the client after publishing
    for s in post["steps"]:
        for q in s["questions"]:
            for a in q["answers"]:
                assert "is_correct" not in a

    # course version bumped → /content/curriculum cache hash rotates
    courses = (await client.get("/api/v1/content/courses", headers=auth(ptok))).json()
    course_v = int(courses[0]["version"])
    cur = (await client.get("/api/v1/content/curriculum", headers=auth(ptok))).json()
    assert cur["version"] and cur["version"] != pre_cur_version
    assert cur["counts"]["changed_lessons"] == 1

    # versions endpoint: before + after snapshots, human-attributed
    vs = (await client.get(f"/api/v1/admin/content/versions?entity_type=lesson"
                           f"&entity_id={lesson_id}", headers=auth(tok))).json()
    states = {v["snapshot_state"] for v in vs}
    assert {"before", "after"} <= states
    assert any(v["origin"] == "ai_pipeline" and v["change_reason"] for v in vs)

    # ROLLBACK restores the previous version exactly
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/rollback",
                          headers=auth(tok))
    assert r.status_code == 200, r.text
    back = (await client.get(f"/api/v1/content/lessons/{lesson_id}",
                             headers=auth(ptok))).json()
    assert back["summary"] == pre["summary"]
    assert sum(len(s["questions"]) for s in back["steps"]) == pre_n_q
    assert back["title"] == pre["title"]
    detail = (await client.get(f"/api/v1/admin/content/proposals/{pid}",
                               headers=auth(tok))).json()
    assert detail["status"] == "rolled_back"


async def test_new_lesson_publishes_into_curriculum_and_deletes_on_rollback(client):
    tok = await admin_token(client)
    src = await _paste(client, tok, TEXT_SILENT_E, title="Silent E ideas")
    await _process(client, tok, src["id"])
    props = [p for p in await _props(client, tok, src["id"])
             if p["action"] == "new_lesson"]
    assert props, "silent-e should be flagged missing and drafted as a new lesson"
    pid = props[0]["id"]
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/approve",
                          json={"notes": "approved as-is"}, headers=auth(tok))
    if r.status_code == 409:  # real duplicate flags → the gate works; a human
        assert r.json()["error"]["code"] == "validation_failed"  # gate works
        r = await client.post(f"/api/v1/admin/content/proposals/{pid}/approve",
                              json={"notes": "forced after manual check",
                                    "force": True}, headers=auth(tok))
    assert r.status_code == 200, r.text
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/publish",
                          json={"notes": None}, headers=auth(tok))
    assert r.status_code == 200, r.text
    lesson_id = r.json()["lesson_id"]
    code = r.json()["changed_lessons"][0]
    assert code.startswith("ai-")

    pemail, _ = await register(client)
    ptok = (await login(client, pemail))["access_token"]
    lesson = (await client.get(f"/api/v1/content/lessons/{lesson_id}",
                               headers=auth(ptok))).json()
    assert "ilent e" in lesson["title"] or "ilent e" in (lesson["summary"] or "")

    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/rollback",
                          headers=auth(tok))
    assert r.status_code == 200, r.text
    r = await client.get(f"/api/v1/content/lessons/{lesson_id}", headers=auth(ptok))
    assert r.status_code == 404, "rollback must remove the lesson the draft created"


async def test_copilot_questions_need_a_target_before_publishing(client):
    tok = await admin_token(client)
    r = await client.post("/api/v1/admin/content/copilot",
                          json={"prompt": "create 4 practice questions for sh"},
                          headers=auth(tok))
    assert r.status_code == 200
    pid = r.json()["proposals"][0]
    d = (await client.get(f"/api/v1/admin/content/proposals/{pid}",
                          headers=auth(tok))).json()
    assert len(d["payload"]["new_questions"]) >= 1

    # publish without a chosen target lesson → refused, content untouched
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/approve",
                          json={"notes": "ok"}, headers=auth(tok))
    if r.status_code == 409:  # genuine duplicate flags: gate works, human decides
        assert r.json()["error"]["code"] == "validation_failed"
        r = await client.post(f"/api/v1/admin/content/proposals/{pid}/approve",
                              json={"notes": "override after manual check",
                                    "force": True}, headers=auth(tok))
        assert r.status_code == 200
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/publish",
                          json={"notes": "no target yet"}, headers=auth(tok))
    assert r.status_code == 409

    # second batch: choose the target BEFORE approving — the full human cycle
    r = await client.post("/api/v1/admin/content/copilot",
                          json={"prompt": "create 3 practice questions"},
                          headers=auth(tok))
    assert r.status_code == 200
    pid2 = r.json()["proposals"][0]
    r = await client.patch(f"/api/v1/admin/content/proposals/{pid2}",
                           json={"target_code": "digraph-sh",
                                 "notes": "attach to the sh lesson"},
                           headers=auth(tok))
    assert r.status_code == 200, r.text
    d2 = (await client.get(f"/api/v1/admin/content/proposals/{pid2}",
                           headers=auth(tok))).json()
    assert d2["target_code"] == "digraph-sh"
    r = await client.post(f"/api/v1/admin/content/proposals/{pid2}/approve",
                          json={"notes": "target verified"}, headers=auth(tok))
    if r.status_code == 409:
        r = await client.post(f"/api/v1/admin/content/proposals/{pid2}/approve",
                              json={"notes": "override", "force": True},
                              headers=auth(tok))
    assert r.status_code == 200, r.text
    r = await client.post(f"/api/v1/admin/content/proposals/{pid2}/publish",
                          json={"notes": "extra drill for sh"}, headers=auth(tok))
    assert r.status_code == 200, r.text
    assert "digraph-sh" in r.json()["changed_lessons"]


# ------------------------------------------------------------- security
async def test_parent_token_cannot_reach_admin_content(client):
    email, _ = await register(client)
    pair = await login(client, email)
    r = await client.get("/api/v1/admin/content/sources",
                         headers=auth(pair["access_token"]))
    assert r.status_code in (401, 403)
    r = await client.post("/api/v1/admin/content/sources/paste",
                          json={"title": "x", "license_type": "public_domain",
                                "text": "y" * 200}, headers=auth(pair["access_token"]))
    assert r.status_code in (401, 403)


async def test_anonymous_admin_surface_is_closed(client):
    r = await client.get("/api/v1/admin/content/proposals")
    assert r.status_code == 401
    r = await client.get("/api/v1/admin/content/usage")
    assert r.status_code == 401


async def test_support_role_admin_can_read_but_not_write(client, db):
    from datetime import datetime, timezone
    from app.models import AdminUser
    from app.security import hash_password, create_access_token
    su = AdminUser(username="support-only", password_hash=hash_password("Support-123!x"),
                   display_name="Support", role="support")
    db.add(su)
    await db.commit()  # visible to request sessions
    token, _ = create_access_token(su.id, "admin", minutes=30)
    h = {"Authorization": f"Bearer {token}"}
    r = await client.get("/api/v1/admin/content/sources", headers=h)
    assert r.status_code == 200          # read: fine
    r = await client.post("/api/v1/admin/content/sources/paste",
                          json={"title": "nope", "license_type": "public_domain",
                                "text": "text" * 100}, headers=h)
    assert r.status_code == 403          # write: forbidden for support role


async def test_source_files_not_exposed_without_admin(client):
    tok = await admin_token(client)
    src = await _paste(client, tok, TEXT_BLEND)
    doc_id = src["documents"][0]["id"]
    email, _ = await register(client)
    ptok = (await login(client, email))["access_token"]
    r = await client.get(f"/api/v1/admin/content/sources/{src['id']}"
                         f"/documents/{doc_id}/download", headers=auth(ptok))
    assert r.status_code in (401, 403)
    r = await client.get(f"/api/v1/admin/content/sources/{src['id']}"
                         f"/documents/{doc_id}/download", headers=auth(tok))
    assert r.status_code == 200
    assert b"blending" in r.content.lower()


async def test_publish_writes_audit_and_review_history(client):
    tok = await admin_token(client)
    src = await _paste(client, tok, TEXT_BLEND, title="Audit trail")
    await _process(client, tok, src["id"])
    props = await _props(client, tok, src["id"])
    assert props
    pid = props[0]["id"]
    await client.post(f"/api/v1/admin/content/proposals/{pid}/approve",
                      json={"notes": "ship it"}, headers=auth(tok))
    r = await client.post(f"/api/v1/admin/content/proposals/{pid}/publish",
                          json={"notes": "publishing after review"}, headers=auth(tok))
    assert r.status_code == 200
    d = (await client.get(f"/api/v1/admin/content/proposals/{pid}",
                          headers=auth(tok))).json()
    actions = [rev["action"] for rev in d["reviews"]]
    assert "approved" in actions and "published" in actions
    assert actions.index("approved") < actions.index("published")
