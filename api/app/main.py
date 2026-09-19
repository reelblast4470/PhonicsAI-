"""PhonicsAI API application factory.

Single deployable process (uvicorn/gunicorn workers share nothing; all state
is Postgres). Routes are versioned under /api/v1; adding /api/v2 later is an
additive, non-breaking move.
"""

import logging
import time

from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from slowapi import Limiter
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address
from sqlalchemy import text

from .config import get_settings
from .db import get_engine
from .errors import install_error_handlers
from .limiter import limiter as shared_limiter
from .routers import (
    admin,
    admin_content,
    analytics_api,
    assessments,
    auth,
    commerce,
    content,
    engagement,
    learners,
    progress,
    support,
    tutor,
)

log = logging.getLogger("phonicsai.api")


def create_app() -> FastAPI:
    settings = get_settings()
    limiter = shared_limiter

    app = FastAPI(
        title="PhonicsAI API", version="1.0.0",
        docs_url="/docs" if settings.environment != "production" else None,
        redoc_url=None,
    )
    app.state.limiter = limiter
    install_error_handlers(app)
    app.add_middleware(SlowAPIMiddleware)
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins_list,
            allow_credentials=False,  # bearer tokens in header; no cookie auth
            allow_methods=["GET", "POST", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type"],
            max_age=600,
        )

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = (
            "no-store" if request.url.path.startswith("/api/v1") else "public, max-age=60"
        )
        if settings.environment == "production":
            response.headers["Strict-Transport-Security"] = (
                "max-age=31536000; includeSubDomains")
        response.headers["X-Request-Duration-Ms"] = f"{(time.perf_counter() - start) * 1000:.0f}"
        return response

    prefix = "/api/v1"
    for r in (auth.router, learners.router, content.router, progress.router,
              assessments.router, assessments.router_list, engagement.router,
              commerce.router, analytics_api.router):
        app.include_router(r, prefix=prefix)
    # admin is mounted under its own guard; user tokens can never reach it
    app.include_router(admin.router, prefix=prefix)
    app.include_router(admin_content.router, prefix=prefix)
    app.include_router(tutor.router, prefix=prefix)
    app.include_router(tutor.admin_router, prefix=prefix)
    app.include_router(support.router, prefix=prefix)
    app.include_router(support.admin_router, prefix=prefix)

    # dev/staging admin console for the Phase-4 pipeline (a thin reference UI
    # over /api/v1/admin/content/*; never mounted in production)
    if settings.environment != "production":
        app.mount(
            "/admin-ui",
            StaticFiles(directory=Path(__file__).parent / "static", html=True),
            name="admin-ui")

    @app.get("/healthz", tags=["ops"])
    async def healthz() -> dict:
        try:
            async with get_engine().connect() as conn:
                await conn.execute(text("SELECT 1"))
            db_ok = True
        except Exception:  # health endpoint must never leak details
            db_ok = False
        return {"status": "ok" if db_ok else "degraded", "database": db_ok,
                "environment": settings.environment}

    return app


app = create_app()
