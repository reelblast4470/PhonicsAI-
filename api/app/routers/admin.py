"""Admin API — a separate universe from user auth.

 * own table, own login route, own token type ('admin' tokens are rejected by
   every user route and vice versa — checked in security.decode typ + tests)
 * every mutation writes admin_audit_logs before returning
 * the future admin dashboard builds on exactly these endpoints; only the
   highest-value operations are implemented in this phase
"""

import hashlib
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Request, Response
from ..limiter import ADMIN_LOGIN_LIMIT, limiter
from sqlalchemy import func, select

from ..db import session_dependency
from ..deps import Admin, DbSession
from ..errors import AppError, not_found, unauthorized
from ..models import (
    AdminAuditLog,
    AdminUser,
    ContentVersion,
    Course,
    Feedback,
    LearnerProfile,
    ParentProfile,
    Subscription,
    SubscriptionEvent,
    User,
)
from ..schemas import AdminLoginIn, AdminTokenOut
from ..security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/admin", tags=["admin"])


async def _audit(db, admin: AdminUser, action: str, *, entity_type=None, entity_id=None,
                 before=None, after=None, request: Request | None = None) -> None:
    ip = request.client.host if request and request.client else None
    db.add(AdminAuditLog(
        admin_id=admin.id, action=action, entity_type=entity_type,
        entity_id=str(entity_id) if entity_id else None,
        before=before, after=after,
        ip_hash=hashlib.sha256(f"s::{ip}".encode()).hexdigest()[:32] if ip else None,
    ))


@router.post("/auth/login", response_model=AdminTokenOut)
@limiter.limit(ADMIN_LOGIN_LIMIT)
async def admin_login(request: Request, response: Response, body: AdminLoginIn, db: DbSession) -> AdminTokenOut:
    admin = await db.scalar(select(AdminUser).where(
        AdminUser.username == body.username.lower()))
    if admin is None or not verify_password(body.password, admin.password_hash):
        raise unauthorized("Username or password is incorrect")
    if not admin.is_active:
        raise AppError("account_disabled", "Admin account is disabled", status_code=403)
    admin.last_login_at = datetime.now(timezone.utc)
    token, _ = create_access_token(admin.id, "admin", minutes=30)
    return AdminTokenOut(access_token=token, expires_in=1800,
                         display_name=admin.display_name, role=admin.role)


@router.get("/users", response_model=list[dict])
async def search_users(db: DbSession, admin: Admin, q: str | None = None,
                       limit: int = 25) -> list[dict]:
    limit = max(1, min(limit, 100))
    stmt = select(User, ParentProfile).join(ParentProfile, ParentProfile.user_id == User.id)
    if q:
        stmt = stmt.where(User.email.ilike(f"%{q[:80]}%"))
    out = []
    stream = await db.stream(stmt.limit(limit))
    async for user, prof in stream:
        n_learners = await db.scalar(select(func.count(LearnerProfile.id)).where(
            LearnerProfile.parent_id == prof.id))
        out.append({"id": str(user.id), "email": user.email, "display_name": prof.display_name,
                    "active": user.is_active, "verified": user.email_verified_at is not None,
                    "learners": n_learners or 0, "created_at": user.created_at.isoformat()})
    return out


@router.post("/users/{user_id}/disable", response_model=dict)
async def disable_user(user_id: UUID, db: DbSession, admin: Admin,
                      request: Request) -> dict:
    user = await db.get(User, user_id)
    if user is None:
        raise not_found("User not found")
    before = {"is_active": user.is_active}
    user.is_active = False
    await _audit(db, admin, "user.disable", entity_type="user", entity_id=user_id,
                 before=before, after={"is_active": False}, request=request)
    return {"ok": True}


@router.patch("/feedback/{feedback_id}", response_model=dict)
async def triage_feedback(feedback_id: UUID, status: str, db: DbSession,
                          admin: Admin, request: Request) -> dict:
    if status not in {"new", "in_progress", "resolved"}:
        raise AppError("bad_status", "status must be new|in_progress|resolved")
    row = await db.get(Feedback, feedback_id)
    if row is None:
        raise not_found("Feedback not found")
    before = {"status": row.status}
    row.status = status
    if status == "resolved":
        row.resolved_at = datetime.now(timezone.utc)
    await _audit(db, admin, "feedback.triage", entity_type="feedback", entity_id=feedback_id,
                 before=before, after={"status": status}, request=request)
    return {"ok": True}


def _course_snapshot(course: Course) -> dict:
    return {
        "slug": course.slug, "title": course.title, "description": course.description,
        "modules": [
            {"title": m.title, "position": m.position,
             "lessons": [{"id": str(ls.id), "title": ls.title, "position": ls.position,
                          "steps": [{"step_type": st.step_type, "position": st.position,
                                     "payload": st.payload,
                                     "questions": [
                                         {"prompt": q.prompt, "points": q.points,
                                          "answers": [{"text": a.text,
                                                       "is_correct": a.is_correct}
                                                       for a in q.answers]}
                                         for q in st.questions]}
                                    for st in ls.steps]}
                             for ls in m.lessons]}
            for m in sorted(course.modules, key=lambda m: m.position)]
        }


@router.post("/content/courses/{course_id}/publish", response_model=dict)
async def publish_course(course_id: UUID, db: DbSession, admin: Admin,
                         request: Request) -> dict:
    course = await db.get(Course, course_id)
    if course is None:
        raise not_found("Course not found")
    snapshot = _course_snapshot(course)
    top = await db.scalar(select(func.max(ContentVersion.version)).where(
        ContentVersion.entity_type == "course", ContentVersion.entity_id == course.id))
    version = (top or 0) + 1
    db.add(ContentVersion(entity_type="course", entity_id=course.id, version=version,
                          payload=snapshot, created_by_admin_id=admin.id))
    before = {"status": course.status}
    course.status = "published"
    course.published_payload = {"version": version}
    await _audit(db, admin, "content.publish_course", entity_type="course",
                 entity_id=course.id, before=before,
                 after={"status": "published", "version": version}, request=request)
    return {"ok": True, "version": version}


@router.post("/content/courses/{course_id}/unpublish", response_model=dict)
async def unpublish_course(course_id: UUID, db: DbSession, admin: Admin,
                           request: Request) -> dict:
    course = await db.get(Course, course_id)
    if course is None:
        raise not_found("Course not found")
    before = {"status": course.status}
    course.status = "draft"
    await _audit(db, admin, "content.unpublish_course", entity_type="course",
                 entity_id=course.id, before=before, after={"status": "draft"},
                 request=request)
    return {"ok": True}


@router.post("/subscriptions/{user_id}/grant", response_model=dict)
async def grant_plus(user_id: UUID, plan_key: str, months: int, db: DbSession,
                     admin: Admin, request: Request) -> dict:
    """Support flow: manually grant/extend Plus (refunds, promos). The only
    path that flips a verified entitlement — hence fully audited."""
    user = await db.get(User, user_id)
    if user is None:
        raise not_found("User not found")
    sub = await db.scalar(select(Subscription).where(Subscription.user_id == user_id))
    if sub is None:
        sub = Subscription(user_id=user_id)
        db.add(sub)
    months = max(1, min(months, 24))
    sub.plan_key = plan_key[:40]
    sub.status = "active"
    sub.store = "manual_grant"
    sub.verified = True
    sub.current_period_end = add_months(datetime.now(timezone.utc), months)
    await db.flush()
    db.add(SubscriptionEvent(subscription_id=sub.id, event="started", source="server",
                            payload={"by_admin": str(admin.id), "months": months}))
    await _audit(db, admin, "subscription.grant", entity_type="subscription",
                 entity_id=sub.id, after={"plan_key": plan_key, "months": months},
                 request=request)
    return {"ok": True}


def add_months(dt: datetime, months: int) -> datetime:
    m = dt.month - 1 + months
    year, month = dt.year + m // 12, m % 12 + 1
    day = min(dt.day, [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
                       else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1])
    return dt.replace(year=year, month=month, day=day)


@router.get("/audit-logs", response_model=list[dict])
async def audit_logs(db: DbSession, admin: Admin, limit: int = 50) -> list[dict]:
    limit = max(1, min(limit, 200))
    out = []
    stream = await db.stream(select(AdminAuditLog).order_by(
        AdminAuditLog.created_at.desc()).limit(limit))
    async for row in stream.scalars():
        out.append({"action": row.action, "entity": f"{row.entity_type}:{row.entity_id}",
                    "admin_id": str(row.admin_id) if row.admin_id else None,
                    "before": row.before, "after": row.after,
                    "created_at": row.created_at.isoformat()})
    return out
