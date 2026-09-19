"""Support intake (Phase 5 seam, closed).

Adults write to us through /support/tickets; the app already targets this
path. Tickets carry NO learner data by contract — the client's SupportMessage
type doesn't even have a field for it, and we validate subject/body length
rather than silently truncating.

The admin queue at /admin/support/tickets is deliberately open to the
`support` role for replies too (unlike the content domain, where support is
read-only): answering parents IS the support job. Every status change and
reply is audited, and a reply lands in the parent's notification list.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response
from sqlalchemy import select

from ..deps import Admin, DbSession, Parent
from ..errors import not_found
from ..limiter import SUPPORT_LIMIT, limiter
from ..models import Notification, SupportTicket
from ..schemas import SupportTicketIn, SupportTicketPatch
from .admin import _audit

router = APIRouter(prefix="/support", tags=["support"])
admin_router = APIRouter(prefix="/admin/support", tags=["admin"])

def _t(t: SupportTicket, *, include_body: bool = True) -> dict:
    out = {
        "id": str(t.id), "subject": t.subject, "status": t.status,
        "locale": t.locale, "app_version": t.app_version,
        "platform": t.platform,
        "created_at": t.created_at.isoformat(),
        "answered_at": t.answered_at.isoformat() if t.answered_at else None,
    }
    if include_body:
        out["body"] = t.body
        out["admin_reply"] = t.admin_reply
    return out


@router.post("/tickets", status_code=201)
@limiter.limit(SUPPORT_LIMIT)
async def create_ticket(request: Request, response: Response,
                        body: SupportTicketIn,
                        parent: Parent, db: DbSession) -> dict:
    ticket = SupportTicket(
        user_id=parent.user.id, subject=body.subject.strip(),
        body=body.body.strip(), locale=body.locale or "en",
        app_version=body.app_version or "", platform=body.platform or "",
        status="open")
    db.add(ticket)
    await db.flush()
    return _t(ticket)


@router.get("/tickets")
async def my_tickets(db: DbSession, parent: Parent) -> dict:
    rows = (await db.execute(
        select(SupportTicket).where(SupportTicket.user_id == parent.user.id)
        .order_by(SupportTicket.created_at.desc()).limit(50))).scalars().all()
    return {"tickets": [_t(t) for t in rows]}


@router.get("/tickets/{ticket_id}")
async def my_ticket(ticket_id: UUID, db: DbSession, parent: Parent) -> dict:
    t = await db.get(SupportTicket, ticket_id)
    if t is None or t.user_id != parent.user.id:
        raise not_found("Ticket not found")
    return _t(t)


@admin_router.get("/tickets")
async def queue(db: DbSession, admin: Admin, status: str | None = None,
                limit: Annotated[int, Query(ge=1, le=200)] = 100) -> dict:
    q = select(SupportTicket).order_by(
        SupportTicket.created_at.asc()).limit(limit)
    if status:
        q = q.where(SupportTicket.status == status)
    rows = (await db.execute(q)).scalars().all()
    return {"tickets": [_t(t) for t in rows]}


@admin_router.patch("/tickets/{ticket_id}")
async def update_ticket(ticket_id: UUID, request: Request, body: SupportTicketPatch,
                        db: DbSession, admin: Admin) -> dict:
    t = await db.get(SupportTicket, ticket_id)
    if t is None:
        raise not_found("Ticket not found")
    before = {"status": t.status, "admin_reply": t.admin_reply}
    t.status = body.status
    if body.admin_reply is not None:
        reply = body.admin_reply.strip()
        if reply:
            t.admin_reply = reply
            t.answered_at = datetime.now(timezone.utc)
            db.add(Notification(
                user_id=t.user_id, kind="support_reply",
                title="Reply from PhonicsAI support",
                body=reply[:400], payload={"ticket_id": str(t.id)}))
    if body.status in ("resolved", "closed"):
        t.answered_at = t.answered_at or datetime.now(timezone.utc)
    await _audit(db, admin, "support.update", entity_type="support_ticket",
                 entity_id=t.id, before=before,
                 after={"status": t.status, "replied": body.admin_reply is not None},
                 request=request)
    await db.flush()
    return _t(t)
