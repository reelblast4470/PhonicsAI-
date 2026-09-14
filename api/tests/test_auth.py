"""Auth flows: registration, login, failures, sessions, reset, verification."""

from datetime import datetime, timedelta, timezone

import pytest

from .conftest import auth, create_learner, extract_verify_token, login, register

pytestmark = pytest.mark.anyio_module if False else []  # asyncio_mode=auto


async def test_register_validation_and_success(client):
    # weak password
    r = await client.post("/api/v1/auth/register", json={
        "email": "weak@mail.phonics.dev", "password": "short1", "display_name": "W"})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "validation_failed"

    # unknown fields rejected
    r = await client.post("/api/v1/auth/register", json={
        "email": "extra@mail.phonics.dev", "password": "Str0ngPassphrase!42",
        "display_name": "E", "is_admin": True})
    assert r.status_code == 422

    email, body = await register(client)
    assert body["email"] == email and body["email_verified"] is False


async def test_duplicate_email_rejected(client):
    email, _ = await register(client)
    r = await client.post("/api/v1/auth/register", json={
        "email": email, "password": "Str0ngPassphrase!42", "display_name": "Twice"})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "email_taken"


async def test_login_success_and_generic_failure(client):
    email, _ = await register(client)
    pair = await login(client, email)
    assert pair["access_token"] and pair["refresh_token"]
    assert pair["user"]["email"] == email

    # wrong password → same shape as unknown email (enumeration-safe)
    r1 = await client.post("/api/v1/auth/login", json={
        "email": email, "password": "WrongPassword123!"})
    r2 = await client.post("/api/v1/auth/login", json={
        "email": "ghost@mail.phonics.dev", "password": "WrongPassword123!"})
    assert r1.status_code == r2.status_code == 401
    assert r1.json()["error"]["message"] == r2.json()["error"]["message"] == \
        "Email or password is incorrect"


async def test_me_requires_valid_token(client):
    r = await client.get("/api/v1/auth/me")
    assert r.status_code == 401
    email, _ = await register(client)
    pair = await login(client, email)
    r = await client.get("/api/v1/auth/me", headers=auth(pair["access_token"]))
    assert r.status_code == 200 and r.json()["email"] == email
    r = await client.get("/api/v1/auth/me", headers=auth(pair["access_token"] + "junk"))
    assert r.status_code == 401


async def test_email_verification_flow(client):
    email, _ = await register(client)
    token = await extract_verify_token(email)
    r = await client.post("/api/v1/auth/verify-email", json={"token": token})
    assert r.status_code == 200 and r.json()["email_verified"] is True
    # single use
    r = await client.post("/api/v1/auth/verify-email", json={"token": token})
    assert r.status_code == 400 and r.json()["error"]["code"] == "invalid_token"


async def test_refresh_rotation_and_reuse_detection(client):
    email, _ = await register(client)
    pair = await login(client, email)

    r = await client.post("/api/v1/auth/refresh", json={"refresh_token": pair["refresh_token"]})
    assert r.status_code == 200
    rotated = r.json()
    assert rotated["refresh_token"] != pair["refresh_token"]

    # old token is now dead; using it kills the family (theft posture)
    r = await client.post("/api/v1/auth/refresh", json={"refresh_token": pair["refresh_token"]})
    assert r.status_code == 401
    r = await client.post("/api/v1/auth/refresh", json={"refresh_token": rotated["refresh_token"]})
    assert r.status_code == 401, "whole family should be revoked after reuse"


async def test_logout_revokes_refresh(client):
    email, _ = await register(client)
    pair = await login(client, email)
    r = await client.post("/api/v1/auth/logout", json={"refresh_token": pair["refresh_token"]})
    assert r.status_code == 204
    r = await client.post("/api/v1/auth/refresh", json={"refresh_token": pair["refresh_token"]})
    assert r.status_code == 401


async def test_password_reset_flow(client):
    # unknown email → identical 202, no leak, no email written
    r = await client.post("/api/v1/auth/password-reset", json={"email": "nobody@mail.phonics.dev"})
    assert r.status_code == 202 and r.json()["accepted"] is True

    email, _ = await register(client)
    # unverified accounts do not get reset emails
    r = await client.post("/api/v1/auth/password-reset", json={"email": email})
    assert r.status_code == 202

    vtok = await extract_verify_token(email)
    await client.post("/api/v1/auth/verify-email", json={"token": vtok})
    r = await client.post("/api/v1/auth/password-reset", json={"email": email})
    assert r.status_code == 202

    from app.mail import latest_email_for

    import re

    raw = latest_email_for(email)
    m = re.search(r"reset-password\?token=([\w-]+)", raw)
    assert m, "reset email should be sent once verified"
    r = await client.post("/api/v1/auth/password-reset/confirm", json={
        "token": m.group(1), "new_password": "FreshNewPassw0rd!7"})
    assert r.status_code == 204

    # old password dead, new alive, sessions wiped
    r = await client.post("/api/v1/auth/login", json={"email": email, "password": "Str0ngPassphrase!42"})
    assert r.status_code == 401
    pair = await login(client, email, "FreshNewPassw0rd!7")
    assert pair["access_token"]


async def test_disabled_account_cannot_log_in(client):
    email, user = await register(client)
    atok = await _super_admin_token(client)
    r = await client.post(f"/api/v1/admin/users/{user['id']}/disable", headers=auth(atok))
    assert r.status_code == 200
    r = await client.post("/api/v1/auth/login", json={"email": email, "password": "Str0ngPassphrase!42"})
    assert r.status_code == 403 and r.json()["error"]["code"] == "account_disabled"


async def _super_admin_token(client) -> str:
    from .conftest import admin_token

    return await admin_token(client)


async def test_account_delete_cascades_everything(client):
    email, user = await register(client)
    pair = await login(client, email)
    tok = pair["access_token"]
    learner = await create_learner(client, tok)
    # some learning data
    r = await client.post(f"/api/v1/learners/{learner['id']}/sessions",
                          json={"kind": "reading"}, headers=auth(tok))
    sid = r.json()["id"]
    await client.post(f"/api/v1/learners/{learner['id']}/sessions/{sid}/events",
                      json={"event_type": "reading_practiced", "payload": {"minutes": 3}},
                      headers=auth(tok))

    r = await client.delete("/api/v1/auth/account", headers=auth(tok))
    assert r.status_code == 204

    from sqlalchemy import func, select

    from app.db import get_session_factory
    from app.models import LearnerProfile, LearningSession

    async with get_session_factory()() as s:
        assert (await s.scalar(select(func.count()).select_from(LearnerProfile)
                               .where(LearnerProfile.id == learner["id"]))) == 0
        assert (await s.scalar(select(func.count()).select_from(LearningSession))) == 0
