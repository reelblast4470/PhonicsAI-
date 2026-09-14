"""Subscriptions. Entitlements flip ONLY on server-verified events; a client
report is recorded (useful for reconciliation) but grants nothing. This is
where the Play/App Store server-side verification worker plugs in later."""

from fastapi import APIRouter
from sqlalchemy import select

from ..analytics import track
from ..deps import DbSession, Parent
from ..models import Subscription, SubscriptionEvent
from ..schemas import SubscriptionEventIn, SubscriptionOut

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])

# SEED pricing for dev; the real catalog/price comes from the store listings.
PLANS = [
    {"key": "plus_monthly", "title": "Plus Monthly", "price": "$7.99",
     "billing_period": "monthly", "trial_days": 7, "origin": "seed-dev"},
    {"key": "plus_yearly", "title": "Plus Yearly", "price": "$49.99",
     "billing_period": "yearly", "trial_days": 14, "savings": "save 48%",
     "origin": "seed-dev"},
]


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
            "note": "Store receipts are applied after server-side verification"}
