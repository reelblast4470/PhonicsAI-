"""Server-side receipt verification (Phase 5 seam, closed).

The client may *report* a purchase (that's what /subscriptions/me/events is
for, and it grants nothing). Premium unlocks only when THIS module confirms
the receipt with the store itself. Pluggable like the AI providers:

* ``BILLING_MODE=mock`` (default in dev/test) — deterministic, accepts any
  non-empty token that isn't marked as a failure token, so the whole flow is
  testable offline. Refused at boot in production.
* ``BILLING_MODE=google_play`` — androidpublisher REST with an ops-supplied
  OAuth access token (no google SDK dependency).
* ``BILLING_MODE=app_store`` — verifyReceipt with the shared secret.
* ``BILLING_MODE=off`` — the verify endpoint returns 503; client-reported
  events keep their reconciliation-only role.

Store transaction ids are unique per row in ``verified_receipts`` — that is
the replay lock: the same receipt can never grant entitlement twice, and
never to a second account.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .config import get_settings
from .errors import AppError
from .models import Subscription, SubscriptionEvent, VerifiedReceipt

# --- catalog ---------------------------------------------------------------
# seed-dev pricing; in a real deployment the price text is what the STORE
# shows — the server only needs the key <-> store product mapping.
PLANS = [
    {"key": "plus_monthly", "store_product": "com.phonicsai.plus.monthly",
     "title": "Plus Monthly", "price": "$7.99", "billing_period": "monthly",
     "trial_days": 7, "origin": "seed-dev"},
    {"key": "plus_yearly", "store_product": "com.phonicsai.plus.yearly",
     "title": "Plus Yearly", "price": "$49.99", "billing_period": "yearly",
     "trial_days": 14, "savings": "save 48%", "origin": "seed-dev"},
    {"key": "plus_lifetime", "store_product": "com.phonicsai.plus.lifetime",
     "title": "Plus Lifetime", "price": "$129.99", "billing_period": "lifetime",
     "trial_days": 0, "origin": "seed-dev"},
]


def plan_for(product_id: str) -> dict | None:
    """Accepts the plan key, the store product id, or the bare suffix
    ('plus.yearly') — clients historically pass any of the three."""
    p = (product_id or "").strip().lower()
    p = re.sub(r"^com\.phonicsai\.", "", p).replace(".", "_").replace("-", "_")
    for plan in PLANS:
        if p in (plan["key"], plan["store_product"],
                 plan["store_product"].split(".")[-1],
                 plan["key"].split("_", 1)[-1]):
            return plan
    return None


@dataclass(frozen=True)
class Verified:
    store: str
    product_id: str
    plan_key: str
    transaction_id: str
    expires_at: datetime | None


def _not_configured(what: str) -> AppError:
    return AppError(
        "billing_not_configured",
        f"Receipt verification is not configured on this server ({what}).",
        503)


def _invalid(why: str) -> AppError:
    return AppError("receipt_invalid", f"The store did not confirm this purchase ({why}).", 400)


def _period_expiry(plan: dict) -> datetime | None:
    now = datetime.now(timezone.utc)
    if plan["billing_period"] == "monthly":
        return now + timedelta(days=31)
    if plan["billing_period"] == "yearly":
        return now + timedelta(days=366)
    return None  # lifetime


# --- verifiers ---------------------------------------------------------------


async def verify_receipt(*, store: str, product_id: str, token: str,
                         transaction_id: str | None = None) -> Verified:
    s = get_settings()
    mode = s.billing_mode
    if mode == "off":
        raise AppError("billing_disabled",
                       "Server-side receipt verification is disabled on this deployment.",
                       503)
    if mode == "mock":
        if s.is_production:  # boot check should make this impossible; belt & braces
            raise _not_configured("mock verifier in production")
        return _verify_mock(store, product_id, token, transaction_id)
    if store != mode:
        raise AppError("store_mismatch",
                       f"This deployment verifies {mode} receipts only.", 400)
    if mode == "google_play":
        return await _verify_google(product_id, token)
    if mode == "app_store":
        return await _verify_appstore(product_id, token)
    raise _not_configured(f"unknown BILLING_MODE {mode!r}")


def _verify_mock(store: str, product_id: str, token: str,
                 transaction_id: str | None) -> Verified:
    tok = (token or "").strip()
    if len(tok) < 8:
        raise _invalid("token too short")
    if re.search(r"\b(fail|invalid|revoked|refund)\b", tok.lower()):
        raise _invalid("simulated store rejection")
    plan = plan_for(product_id)
    if plan is None:
        raise AppError("unknown_product", f"Unknown plan/product {product_id!r}.", 400)
    txn = transaction_id or f"mock-{hashlib.sha1(f'{store}:{tok}'.encode()).hexdigest()[:24]}"
    return Verified(store=store, product_id=product_id, plan_key=plan["key"],
                    transaction_id=txn, expires_at=_period_expiry(plan))


async def _verify_google(product_id: str, token: str) -> Verified:
    s = get_settings()
    if not s.google_access_token or not s.google_package:
        raise _not_configured("GOOGLE_ACCESS_TOKEN / GOOGLE_PACKAGE")
    url = ("https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"
           f"{quote(s.google_package)}/purchases/products/{quote(product_id)}"
           f"/tokens/{quote(token)}")
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(url, headers={"Authorization": f"Bearer {s.google_access_token}"})
    if r.status_code == 401 or r.status_code == 403:
        raise _not_configured("Play access token rejected")
    if r.status_code == 404:
        raise _invalid("no such purchase token")
    if r.status_code != 200:
        raise _invalid(f"play said http {r.status_code}")
    data = r.json()
    state = int(data.get("purchaseState", 1))
    if state == 1:
        raise _invalid("purchase was cancelled")
    if state == 2:
        raise _invalid("purchase is pending")
    if int(data.get("consumptionState", 0)) == 1:
        raise _invalid("purchase was refunded")
    plan = plan_for(product_id)
    if plan is None:
        raise AppError("unknown_product", f"Store product {product_id!r} is not in our catalog.", 400)
    exp = data.get("expirationTimeMillis")
    expires = (datetime.fromtimestamp(int(exp) / 1000, tz=timezone.utc)
               if exp and plan["billing_period"] != "lifetime" else _period_expiry(plan))
    return Verified(store="google_play", product_id=product_id, plan_key=plan["key"],
                    transaction_id=data.get("orderId") or f"g-{hashlib.sha1(token.encode()).hexdigest()[:24]}",
                    expires_at=expires)


async def _verify_appstore(product_id: str, token: str) -> Verified:
    s = get_settings()
    if not s.appstore_shared_secret:
        raise _not_configured("APPSTORE_SHARED_SECRET")
    url = ("https://sandbox.itunes.apple.com/verifyReceipt" if s.appstore_sandbox
           else "https://buy.itunes.apple.com/verifyReceipt")
    payload = {"receipt-data": token, "password": s.appstore_shared_secret,
               "exclude-old-transactions": True}
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.post(url, json=payload)
        data = r.json() if r.content else {}
        if data.get("status") == 21007:  # sandbox receipt sent to prod
            alt = ("https://buy.itunes.apple.com/verifyReceipt" if s.appstore_sandbox
                   else "https://sandbox.itunes.apple.com/verifyReceipt")
            r = await client.post(alt, json=payload)
            data = r.json() if r.content else {}
    if data.get("status") != 0:
        raise _invalid(f"app store said status {data.get('status')}")
    latest = (data.get("latest_receipt_info") or [{}])[-1]
    exp_ms = latest.get("expires_date_ms")
    plan = plan_for(product_id)
    if plan is None:
        raise AppError("unknown_product", f"Store product {product_id!r} is not in our catalog.", 400)
    expires = (datetime.fromtimestamp(int(exp_ms) / 1000, tz=timezone.utc) if exp_ms
               and plan["billing_period"] != "lifetime" else _period_expiry(plan))
    txn = latest.get("original_transaction_id") or latest.get("transaction_id") \
        or f"a-{hashlib.sha1(token.encode()).hexdigest()[:24]}"
    return Verified(store="app_store", product_id=product_id, plan_key=plan["key"],
                    transaction_id=str(txn), expires_at=expires)


# --- grant -------------------------------------------------------------------


async def apply_verified(db: AsyncSession, user_id, v: Verified, *,
                         first_time: bool) -> Subscription:
    """Idempotent entitlement write. Runs inside the caller's transaction —
    the receipt row and the subscription flip commit or vanish together."""
    sub = await db.scalar(select(Subscription).where(Subscription.user_id == user_id))
    if sub is None:
        sub = Subscription(user_id=user_id, plan_key=None, status="free")
        db.add(sub)
        await db.flush()
    sub.plan_key = v.plan_key
    sub.store = v.store
    sub.status = "active"
    sub.verified = True
    sub.current_period_end = v.expires_at
    sub.cancel_at_period_end = False
    db.add(SubscriptionEvent(
        subscription_id=sub.id, event="renewed" if not first_time else "started",
        source="server_verified",
        payload={"store": v.store, "product_id": v.product_id,
                 "transaction_id": v.transaction_id, "first_time": first_time}))
    await db.flush()
    return sub


def receipt_row(v: Verified, user_id) -> VerifiedReceipt:
    return VerifiedReceipt(
        user_id=user_id, store=v.store, product_id=v.product_id,
        transaction_id=v.transaction_id, plan_key=v.plan_key,
        expires_at=v.expires_at,
        raw={"verified_via": get_settings().billing_mode})


async def find_receipt(db: AsyncSession, v: Verified) -> VerifiedReceipt | None:
    return await db.scalar(select(VerifiedReceipt).where(
        VerifiedReceipt.store == v.store,
        VerifiedReceipt.transaction_id == v.transaction_id))
