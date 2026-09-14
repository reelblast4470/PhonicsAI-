"""Authentication + authorization dependencies.

The rule these encode: *a client-supplied id is a request, a server-side
ownership check is permission.* `resolve_learner` is the only path any
learner-scoped route uses; it 404s (not 403s) foreign resources so probing
ids cannot enumerate other families' data.
"""

from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import session_dependency
from .errors import forbidden, not_found, unauthorized
from .models import AdminUser, LearnerProfile, ParentProfile, User
from .security import decode_access_token

bearer = HTTPBearer(auto_error=False)
DbSession = Annotated[AsyncSession, Depends(session_dependency)]


@dataclass(frozen=True)
class AuthContext:
    user: User
    parent: ParentProfile


async def current_parent(
    db: DbSession,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> AuthContext:
    if creds is None:
        raise unauthorized("Missing bearer token")
    claims = decode_access_token(creds.credentials, "user")
    user = await db.get(User, UUID(claims["sub"]))
    if user is None or not user.is_active:
        raise unauthorized("Account is not active")
    parent = await db.scalar(select(ParentProfile).where(ParentProfile.user_id == user.id))
    if parent is None:  # defensive: users without a parent profile cannot act as parents
        raise forbidden("No parent profile")
    return AuthContext(user=user, parent=parent)


async def current_learner_scope(
    db: DbSession,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> LearnerProfile:
    """Learner-device tokens: only ever their own profile."""
    if creds is None:
        raise unauthorized("Missing bearer token")
    claims = decode_access_token(creds.credentials, "learner")
    learner = await db.get(LearnerProfile, UUID(claims["learner"]))
    if learner is None or learner.archived:
        raise unauthorized("Learner profile is not available")
    return learner


async def resolve_learner(
    db: DbSession,
    learner_id: UUID,
    parent: AuthContext | None = None,
    learner: LearnerProfile | None = None,
) -> LearnerProfile:
    """The authorization choke-point for /learners/{id} routes.

    Exactly one identity applies: a parent who owns the row, or a learner
    token scoped to that row. Anything else is 404.
    """
    if learner is not None:
        if learner.id != learner_id:
            raise not_found("Learner not found")
        return learner
    assert parent is not None
    row = await db.get(LearnerProfile, learner_id)
    if row is None or row.parent_id != parent.parent.id or row.archived:
        raise not_found("Learner not found")
    return row


async def current_admin(
    db: DbSession,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> AdminUser:
    if creds is None:
        raise unauthorized("Missing admin token")
    claims = decode_access_token(creds.credentials, "admin")
    admin = await db.get(AdminUser, UUID(claims["sub"]))
    if admin is None or not admin.is_active:
        raise unauthorized("Admin account is not active")
    return admin


Parent = Annotated[AuthContext, Depends(current_parent)]
LearnerScoped = Annotated[LearnerProfile, Depends(current_learner_scope)]
Admin = Annotated[AdminUser, Depends(current_admin)]


# --- dual identity: learner-device routes accept the parent's user token too.
# The child never holds credentials; the app requests a scoped learner token.


@dataclass(frozen=True)
class Actor:
    parent: "AuthContext | None" = None
    learner: LearnerProfile | None = None


async def actor_dependency(
    db: DbSession,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> Actor:
    from .errors import AppError

    if creds is None:
        raise unauthorized("Missing bearer token")
    try:
        claims = decode_access_token(creds.credentials, "user")
    except AppError:
        claims = decode_access_token(creds.credentials, "learner")
        learner = await db.get(LearnerProfile, UUID(claims["learner"]))
        if learner is None or learner.archived:
            raise unauthorized("Learner profile is not available")
        return Actor(learner=learner)
    user = await db.get(User, UUID(claims["sub"]))
    if user is None or not user.is_active:
        raise unauthorized("Account is not active")
    parent = await db.scalar(select(ParentProfile).where(ParentProfile.user_id == user.id))
    if parent is None:
        raise forbidden("No parent profile")
    return Actor(parent=AuthContext(user=user, parent=parent))


ActorDep = Annotated[Actor, Depends(actor_dependency)]


async def learner_for_actor(db: AsyncSession, learner_id: UUID, actor: Actor) -> LearnerProfile:
    """Single authorization path for every learner-scoped endpoint: parent must
    own the learner; a learner token may only touch its own id. 404 otherwise
    (never 403 — cross-family probes must not learn that the id exists)."""
    row = await db.get(LearnerProfile, learner_id)
    if row is None or row.archived:
        raise not_found("Learner not found")
    if actor.learner is not None:
        if actor.learner.id != row.id:
            raise not_found("Learner not found")
        return row
    assert actor.parent is not None
    if row.parent_id != actor.parent.parent.id:
        raise not_found("Learner not found")
    return row


async def require_parent_owns(db: AsyncSession, parent: "AuthContext", learner_id: UUID) -> LearnerProfile:
    from .models import LearnerProfile as _LP

    row = await db.get(_LP, learner_id)
    if row is None or row.parent_id != parent.parent.id:
        raise not_found("Learner not found")
    return row
