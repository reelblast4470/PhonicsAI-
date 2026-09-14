"""Auth: register, verify email, login, refresh (rotating), logout,
password reset, learner-device tokens, account deletion.

Deliberate choices:
 * Login and reset are enumeration-safe: unknown email and wrong password
   produce the *same* 401/202 shape.
 * Refresh rotation with reuse detection — presenting an already-rotated
   token revokes the entire family (stolen-token posture).
 * Unverified accounts may log in (parents get nudged by email), but
   password-reset emails are only sent to verified addresses, so a takeover
   via typo'd email can't lock a real owner out.
"""

import hashlib
import logging
import uuid as uuidlib
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError

from ..analytics import track
from ..config import get_settings
from ..deps import DbSession, Parent
from ..errors import AppError, unauthorized
from ..mail import send_email
from ..models import (
    EmailToken,
    LearnerProfile,
    ParentProfile,
    RefreshSession,
    User,
)
from ..schemas import (
    LearnerTokenOut,
    LoginIn,
    LogoutIn,
    PasswordResetConfirmIn,
    PasswordResetRequestIn,
    RefreshIn,
    RegisterIn,
    TokenPairOut,
    UserOut,
    VerifyEmailIn,
)
from ..security import (
    check_password_policy,
    create_access_token,
    hash_password,
    hash_token,
    new_opaque_token,
    token_matches,
    verify_password,
)
from ..limiter import AUTH_LIMIT, LOGIN_LIMIT, REGISTER_LIMIT, limiter

log = logging.getLogger("phonicsai.auth")
router = APIRouter(prefix="/auth", tags=["auth"])

GENERIC_BAD_CREDENTIALS = "Email or password is incorrect"


def _client_ip(request: Request) -> str | None:
    hops = get_settings().trusted_proxy_hops
    if hops > 0 and (xff := request.headers.get("x-forwarded-for")):
        return xff.split(",")[-hops].strip()
    return request.client.host if request.client else None


def _ip_hash(ip: str | None) -> str | None:
    if not ip:
        return None
    return hashlib.sha256(f"phonicsai-salt::{ip}".encode()).hexdigest()[:32]


def _user_out(user: User, parent: ParentProfile) -> UserOut:
    return UserOut(
        id=user.id, email=user.email, display_name=parent.display_name,
        locale=parent.locale, email_verified=user.email_verified_at is not None,
        created_at=user.created_at,
    )


async def _issue_session(db, user: User, request: Request) -> tuple[str, str, datetime]:
    """One login = one token family; refreshes extend the family, logouts and
    reuse-detection kill it."""
    s = get_settings()
    access, _exp = create_access_token(user.id, "user")
    refresh = new_opaque_token()
    db.add(
        RefreshSession(
            user_id=user.id,
            token_hash=hash_token(refresh),
            family_id=uuidlib.uuid4(),
            user_agent=(request.headers.get("user-agent") or "")[:255] or None,
            ip_hash=_ip_hash(_client_ip(request)),
            expires_at=datetime.now(timezone.utc) + timedelta(days=s.refresh_token_days),
        )
    )
    return access, refresh, _exp


@router.post("/register", status_code=201, response_model=UserOut)
@limiter.limit(REGISTER_LIMIT)
async def register(request: Request, response: Response, body: RegisterIn,
                   db: DbSession) -> UserOut:
    if err := check_password_policy(body.password):
        raise AppError("weak_password", err)
    email = body.email.lower()
    user = User(email=email, password_hash=hash_password(body.password))
    db.add(user)
    try:
        await db.flush()
    except IntegrityError:
        # Same response shape as success would leak existence; 409 on a form
        # field is the accepted trade-off for the signup flow (login path
        # stays enumeration-safe).
        raise AppError("email_taken", "That email is already registered") from None
    parent = ParentProfile(user_id=user.id, display_name=body.display_name, locale=body.locale)
    db.add(parent)
    await db.flush()

    token = new_opaque_token()
    db.add(EmailToken(user_id=user.id, purpose="verify", token_hash=hash_token(token),
                      expires_at=datetime.now(timezone.utc)
                      + timedelta(hours=get_settings().email_verification_hours)))
    await track(db, "registration", user_id=user.id, properties={"locale": body.locale})
    link = f"{get_settings().app_public_base}/verify-email?token={token}"
    send_email(to=email, subject="Verify your PhonicsAI email",
               body=f"Welcome, {body.display_name}!\n\nConfirm this address:\n{link}\n")
    return _user_out(user, parent)


@router.post("/verify-email", response_model=UserOut)
async def verify_email(request: Request, body: VerifyEmailIn,
                       db: DbSession) -> UserOut:
    row = await db.scalar(
        select(EmailToken).where(EmailToken.purpose == "verify",
                                 EmailToken.token_hash == hash_token(body.token),
                                 EmailToken.used_at.is_(None))
    )
    now = datetime.now(timezone.utc)
    if row is None or row.expires_at < now:
        raise AppError("invalid_token", "This verification link is invalid or has expired",
                       status_code=400)
    row.used_at = now
    user = await db.get(User, row.user_id)
    if user.email_verified_at is None:
        user.email_verified_at = now
        await track(db, "email_verified", user_id=user.id)
    parent = await db.scalar(select(ParentProfile).where(ParentProfile.user_id == user.id))
    return _user_out(user, parent)


@router.post("/login", response_model=TokenPairOut)
@limiter.limit(LOGIN_LIMIT)
async def login(request: Request, response: Response, body: LoginIn,
                db: DbSession) -> TokenPairOut:
    user = await db.scalar(select(User).where(User.email == body.email.lower()))
    if user is None or not verify_password(body.password, user.password_hash):
        raise unauthorized(GENERIC_BAD_CREDENTIALS)
    if not user.is_active:
        raise AppError("account_disabled", "This account is disabled", status_code=403)
    s = get_settings()
    access, refresh, _ = await _issue_session(db, user, request)
    parent = await db.scalar(select(ParentProfile).where(ParentProfile.user_id == user.id))
    await db.execute(update(User).where(User.id == user.id)
                     .values(last_login_at=datetime.now(timezone.utc)))
    return TokenPairOut(
        access_token=access,
        expires_in=s.access_token_minutes * 60,
        refresh_token=refresh,
        user=_user_out(user, parent),
    )


@router.post("/refresh", response_model=TokenPairOut)
@limiter.limit(AUTH_LIMIT)
async def refresh(request: Request, response: Response, body: RefreshIn,
                  db: DbSession) -> TokenPairOut:
    """Rotate the refresh token. Reuse of a rotated/revoked token nukes the
    family — a stolen snapshot can't ride silently."""
    now = datetime.now(timezone.utc)
    row = await db.scalar(
        select(RefreshSession).where(RefreshSession.token_hash == hash_token(body.refresh_token))
    )
    if row is None or row.expires_at < now:
        raise unauthorized(GENERIC_BAD_CREDENTIALS)
    if row.revoked_at is not None:
        # Reuse detected: revoke the WHOLE family in its own committed
        # transaction — raising would roll back the request-scoped session and
        # leave the stolen lineage usable, which is the opposite of the point.
        from ..db import get_session_factory

        async with get_session_factory()() as kill:
            await kill.execute(
                update(RefreshSession)
                .where(RefreshSession.family_id == row.family_id,
                       RefreshSession.revoked_at.is_(None))
                .values(revoked_at=now)
            )
            await kill.commit()
        log.warning("refresh reuse detected for user=%s; family revoked", row.user_id)
        raise unauthorized("Session expired; sign in again")
    row.revoked_at = now
    row.rotated_at = now
    user = await db.get(User, row.user_id)
    if user is None or not user.is_active:
        raise unauthorized("Account is not active")
    s = get_settings()
    access, exp = create_access_token(user.id, "user")
    new_refresh = new_opaque_token()
    db.add(RefreshSession(user_id=user.id, token_hash=hash_token(new_refresh),
                          family_id=row.family_id, user_agent=row.user_agent,
                          ip_hash=row.ip_hash,
                          expires_at=now + timedelta(days=s.refresh_token_days)))
    parent = await db.scalar(select(ParentProfile).where(ParentProfile.user_id == user.id))
    return TokenPairOut(access_token=access, expires_in=s.access_token_minutes * 60,
                        refresh_token=new_refresh, user=_user_out(user, parent))


@router.post("/logout", status_code=204)
async def logout(request: Request, body: LogoutIn,
                 db: DbSession) -> None:
    row = await db.scalar(
        select(RefreshSession).where(RefreshSession.token_hash == hash_token(body.refresh_token))
    )
    if row is not None:
        row.revoked_at = datetime.now(timezone.utc)


@router.post("/password-reset", status_code=202)
@limiter.limit(AUTH_LIMIT)
async def password_reset_request(request: Request, response: Response, body: PasswordResetRequestIn,
                                 db: DbSession) -> dict:
    """Always 202. The email is only *sent* when the account exists and is
    verified — a reset token to an unclaimed typo address is how you learn an
    account exists."""
    accepted = {"accepted": True,
                "message": "If that email has an account, a reset link is on its way."}
    user = await db.scalar(select(User).where(User.email == body.email.lower()))
    if user is None or user.email_verified_at is None or not user.is_active:
        return accepted
    token = new_opaque_token()
    db.add(EmailToken(user_id=user.id, purpose="reset", token_hash=hash_token(token),
                      expires_at=datetime.now(timezone.utc)
                      + timedelta(minutes=get_settings().password_reset_minutes)))
    link = f"{get_settings().app_public_base}/reset-password?token={token}"
    send_email(to=user.email, subject="Reset your PhonicsAI password",
               body=f"A password reset was requested.\n\n{link}\n\n"
                    f"It expires in {get_settings().password_reset_minutes} minutes. "
                    "If this wasn't you, no action is needed.")
    return accepted


@router.post("/password-reset/confirm", status_code=204)
@limiter.limit(AUTH_LIMIT)
async def password_reset_confirm(request: Request, response: Response, body: PasswordResetConfirmIn,
                                 db: DbSession) -> None:
    now = datetime.now(timezone.utc)
    row = await db.scalar(
        select(EmailToken).where(EmailToken.purpose == "reset",
                                 EmailToken.token_hash == hash_token(body.token),
                                 EmailToken.used_at.is_(None))
    )
    if row is None or row.expires_at < now:
        raise AppError("invalid_token", "This reset link is invalid or has expired",
                       status_code=400)
    if err := check_password_policy(body.new_password):
        raise AppError("weak_password", err)
    row.used_at = now
    user = await db.get(User, row.user_id)
    user.password_hash = hash_password(body.new_password)
    # every existing session dies with the old password
    await db.execute(update(RefreshSession)
                     .where(RefreshSession.user_id == user.id,
                            RefreshSession.revoked_at.is_(None))
                     .values(revoked_at=now))


@router.get("/me", response_model=UserOut)
async def me(parent: Parent, db: DbSession) -> UserOut:
    return _user_out(parent.user, parent.parent)


@router.delete("/account", status_code=204)
async def delete_account(parent: Parent,
                         db: DbSession) -> None:
    """Hard delete with DB-level cascade (learners, progress, analytics…).
    A production deployment additionally queues a backup-invalidation job —
    see docs in api/README.md (backup strategy + retention)."""
    await track(db, "account_deleted", user_id=parent.user.id)
    await db.delete(parent.user)


@router.post("/learner-token", response_model=LearnerTokenOut)
async def learner_token(parent: Parent, learner_id: UUID,
                        db: DbSession) -> LearnerTokenOut:
    """Short-lived device token scoped to exactly one learner. The app hands
    this to the same ApiClient when the child (not the parent) is acting."""
    row = await db.get(LearnerProfile, learner_id)
    if row is None or row.parent_id != parent.parent.id or row.archived:
        from ..errors import not_found

        raise not_found("Learner not found")
    s = get_settings()
    access, exp = create_access_token(parent.user.id, "learner", learner_id=learner_id,
                                      hours=s.learner_token_hours)
    return LearnerTokenOut(access_token=access,
                           expires_in=s.learner_token_hours * 3600,
                           learner_id=learner_id)
