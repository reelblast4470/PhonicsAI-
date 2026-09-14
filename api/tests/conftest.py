"""Test harness: real Postgres (phonicsai_test), real HTTP layer (ASGI),
real seeding. No mocks except the deliberate ones named in tests."""

import asyncio
import os
import re
import uuid
from datetime import datetime, timezone

import httpx
import pytest

os.environ["DATABASE_URL"] = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://phonicsai:devlocal_only_not_a_secret@127.0.0.1:5432/phonicsai_test",
)
os.environ["ENVIRONMENT"] = "test"
os.environ["OUTBOX_DIR"] = "/tmp/phonicsai-outbox-test"
os.environ["JWT_SECRET"] = "test-secret-not-for-prod"

from sqlalchemy import text  # noqa: E402

from app.db import Base, get_engine, get_session_factory  # noqa: E402
from app.limiter import limiter  # noqa: E402
from app.main import create_app  # noqa: E402
from app import models  # noqa: E402,F401  (register metadata)
from app.mail import latest_email_for  # noqa: E402
from app.seed import seed_all  # noqa: E402


@pytest.fixture(scope="session")
def app():
    # Rate limiting off by default; the one rate-limit test re-enables it.
    limiter.enabled = False
    return create_app()


@pytest.fixture(scope="session", autouse=True)
async def _schema():
    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


_TABLES = ", ".join(f'"{t.name}"' for t in reversed(list(Base.metadata.sorted_tables)))


@pytest.fixture
async def db():
    """Per-test clean slate + seeded catalog."""
    factory = get_session_factory()
    async with factory() as session:
        await session.execute(text(f"TRUNCATE {_TABLES} RESTART IDENTITY CASCADE"))
        await session.commit()
        await seed_all(session, include_admin=True)
        yield session


@pytest.fixture
async def client(app, db):
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture
async def db_read():
    """Separate session for direct row assertions."""
    async with get_session_factory()() as session:
        yield session


async def register(client, *, email=None, password="Str0ngPassphrase!42", name="Mom Test"):
    email = email or f"u{uuid.uuid4().hex[:10]}@mail.phonics.dev"
    r = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "display_name": name},
    )
    assert r.status_code == 201, r.text
    return email, r.json()


async def login(client, email, password="Str0ngPassphrase!42"):
    r = await client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return r.json()


@pytest.fixture
async def parent_client(client):
    """Authenticated parent; returns (client, access_token, refresh_token)."""
    email, _ = await register(client)
    pair = await login(client, email)
    return client, pair["access_token"], pair["refresh_token"]


def auth(token):
    return {"Authorization": f"Bearer {token}"}


async def extract_verify_token(email: str) -> str:
    raw = latest_email_for(email)
    assert raw, "no verification email was written"
    m = re.search(r"verify-email\?token=([\w-]+)", raw)
    assert m, raw
    return m.group(1)


async def create_learner(client, token, *, name="Ari", **kw) -> dict:
    body = {"display_name": name, "daily_target_minutes": 15, **kw}
    r = await client.post("/api/v1/learners", json=body, headers=auth(token))
    assert r.status_code == 201, r.text
    return r.json()


async def first_lesson_id(client, token) -> tuple[str, str]:
    r = await client.get("/api/v1/content/courses", headers=auth(token))
    assert r.status_code == 200, r.text
    course = r.json()[0]
    lesson = course["modules"][0]["lessons"][0]
    return course["id"], lesson["id"]


async def first_question(client, token, lesson_id) -> dict:
    """Pull real question/answer ids from the lesson. Also asserts the content
    API never exposes is_correct."""
    r = await client.get(f"/api/v1/content/lessons/{lesson_id}", headers=auth(token))
    assert r.status_code == 200, r.text
    lesson = r.json()
    for step in lesson["steps"]:
        for q in step["questions"]:
            assert all("is_correct" not in a for a in q["answers"]), "content API leaked answers!"
            return {"question_id": q["id"], "answers": q["answers"]}
    raise AssertionError("lesson had no questions")


ADMIN_CREDS = ("admin-dev", "Changeme-First!23")


async def admin_token(client) -> str:
    r = await client.post(
        "/api/v1/admin/auth/login",
        json={"username": ADMIN_CREDS[0], "password": ADMIN_CREDS[1]},
    )
    assert r.status_code == 200, r.text
    return r.json()["access_token"]
