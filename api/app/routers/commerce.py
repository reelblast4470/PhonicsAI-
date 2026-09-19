"""Subscriptions. Entitlements flip ONLY on server-verified events; a client
report is recorded (useful for reconciliation) but grants nothing. Verification
lives in app/billing.py (BILLING_MODE=mock|google_play|app_store|off) and the
replay lock is the unique (store, transaction_id) row in verified_receipts."""

from fastapi import APIRouter, Request, Response
from sqlalchemy import select

from .. import billing
from ..analytics import track
from ..deps import DbSession, Parent
from ..errors import AppError
from ..limiter import limiter
from ..models import Subscription, SubscriptionEvent
from ..schemas import ReceiptIn, SubscriptionEventIn, SubscriptionOut

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])

PLANS = billing.PLANS  # catalog + store-product mapping live in billing.py


@router.get("/plans", response_model=list[dict])
async def plans() -> list[dict]:
    return PLANS


@router.get("/me", response_model=SubscriptionOut)
async def my_subscription(parent: Parent, db: DbSession) -> SubscriptionOut:
    sub = await db.scalar(select(Subscription).where(Subscription.user_id == parent.user.id))
    if sub is None:
        return SubscriptionOut(plan_key=None, status="free", store="none", verified=False,
                               current_period_end=None, cancel_at_period_end=False)
    return SubscriptionOut(plan_key=sub.plan_key, status=sub.status, store=sub.store,
                           verified=sub.verified, current_period_end=sub.current_period_end,
                           cancel_at_period_end=sub.cancel_at_period_end)


@router.post("/me/events", response_model=dict, status_code=202)
async def report_event(body: SubscriptionEventIn, parent: Parent, db: DbSession) -> dict:
    sub = await db.scalar(select(Subscription).where(Subscription.user_id == parent.user.id))
    if sub is None:
        sub = Subscription(user_id=parent.user.id, plan_key=body.plan_key,
                           store="client_reported", status="free", verified=False)
        db.add(sub)
        await db.flush()
    db.add(SubscriptionEvent(subscription_id=sub.id, event=body.event,
                            source="client_reported",
                            payload={"plan_key": body.plan_key,
                                     "receipt_received": body.store_receipt is not None}))
    await db.flush()
    return {"accepted": True, "entitlement_changed": False,
            "note": "Store receipts are applied after server-side verification "
                    "(POST /subscriptions/me/receipt)"}


@router.post("/me/receipt", response_model=dict)
@limiter.limit("20/minute")
async def verify_receipt(request: Request, response: Response, body: ReceiptIn,
                         parent: Parent, db: DbSession) -> dict:
    """The ONLY endpoint that flips entitlements. The store itself vouches
    for the receipt; our answer, not the client's token, decides what
    unlocks."""
    v = await billing.verify_receipt(store=body.store, product_id=body.product_id,
                                      token=body.purchase_token,
                                      transaction_id=body.transaction_id)
    existing = await billing.find_receipt(db, v)
    if existing is not None and existing.user_id != parent.user.id:
        raise AppError("receipt_used_elsewhere",
                       "This purchase is already linked to a different account.", 409)
    if existing is None:
        db.add(billing.receipt_row(v, parent.user.id))
        await db.flush()
    sub = await billing.apply_verified(db, parent.user.id, v,
                                       first_time=existing is None)
    return {"plan_key": sub.plan_key, "status": sub.status, "store": sub.store,
            "verified": sub.verified,
            "current_period_end": sub.current_period_end,
            "cancel_at_period_end": sub.cancel_at_period_end,
            "granted": True, "already_recorded": existing is not None}
