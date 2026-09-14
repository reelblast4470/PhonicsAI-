"""Authorization: parent↔learner boundaries, learner-token scoping, admin
separation. These are the tests that matter most for a kids' product."""

import pytest

from .conftest import admin_token, auth, create_learner, login, register


async def test_parent_only_sees_own_learners(client):
    email_a, _ = await register(client)
    tok_a = (await login(client, email_a))["access_token"]
    email_b, _ = await register(client)
    tok_b = (await login(client, email_b))["access_token"]

    learner_a = await create_learner(client, tok_a)
    assert len((await client.get("/api/v1/learners", headers=auth(tok_a))).json()) == 1
    assert (await client.get("/api/v1/learners", headers=auth(tok_b))).json() == []

    # B probing A's learner id gets 404 (no existence leak), not 403
    r = await client.get(f"/api/v1/learners/{learner_a['id']}", headers=auth(tok_b))
    assert r.status_code == 404


async def test_learner_token_is_scoped_to_one_child(client):
    email, _ = await register(client)
    tok = (await login(client, email))["access_token"]
    a = await create_learner(client, tok, name="Ari")
    b = await create_learner(client, tok, name="Bo")

    r = await client.post(f"/api/v1/auth/learner-token?learner_id={a['id']}", headers=auth(tok))
    assert r.status_code == 200
    ltok = r.json()["access_token"]

    # own learner: fine
    r = await client.get(f"/api/v1/learners/{a['id']}/snapshot", headers=auth(ltok))
    assert r.status_code == 200
    # sibling: 404 even though same family — the token is the leash
    r = await client.get(f"/api/v1/learners/{b['id']}/snapshot", headers=auth(ltok))
    assert r.status_code == 404
    # parent-only surfaces: learner tokens cannot use them
    r = await client.get("/api/v1/learners", headers=auth(ltok))
    assert r.status_code == 401
    r = await client.get("/api/v1/auth/me", headers=auth(ltok))
    assert r.status_code == 401


async def test_learner_token_for_foreign_child_is_refused(client):
    email_a, _ = await register(client)
    tok_a = (await login(client, email_a))["access_token"]
    foreign = await create_learner(client, tok_a)
    email_b, _ = await register(client)
    tok_b = (await login(client, email_b))["access_token"]
    r = await client.post(f"/api/v1/auth/learner-token?learner_id={foreign['id']}",
                          headers=auth(tok_b))
    assert r.status_code == 404


async def test_progress_must_go_through_authorized_learner(client):
    email_a, _ = await register(client)
    tok_a = (await login(client, email_a))["access_token"]
    email_b, _ = await register(client)
    tok_b = (await login(client, email_b))["access_token"]
    learner_a = await create_learner(client, tok_a)

    # B cannot open a session on A's learner
    r = await client.post(f"/api/v1/learners/{learner_a['id']}/sessions",
                          json={"kind": "lesson"}, headers=auth(tok_b))
    assert r.status_code == 404
    # and cannot even forge a snapshot read
    r = await client.get(f"/api/v1/learners/{learner_a['id']}/snapshot", headers=auth(tok_b))
    assert r.status_code == 404


async def test_admin_and_user_realms_never_mix(client):
    atok = await admin_token(client)
    email, _ = await register(client)
    utok = (await login(client, email))["access_token"]

    # user token → admin route
    r = await client.get("/api/v1/admin/users", headers=auth(utok))
    assert r.status_code == 401
    # admin token → parent route
    r = await client.get("/api/v1/learners", headers=auth(atok))
    assert r.status_code == 401
    # admin can see users
    r = await client.get("/api/v1/admin/users", headers=auth(atok))
    assert r.status_code == 200 and len(r.json()) >= 1


async def test_deleted_learner_is_invisible(client):
    email, _ = await register(client)
    tok = (await login(client, email))["access_token"]
    learner = await create_learner(client, tok)
    r = await client.delete(f"/api/v1/learners/{learner['id']}", headers=auth(tok))
    assert r.status_code == 204
    r = await client.get(f"/api/v1/learners/{learner['id']}", headers=auth(tok))
    assert r.status_code == 404
