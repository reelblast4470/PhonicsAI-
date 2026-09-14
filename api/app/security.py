"""Password hashing, JWT issuing/verification, opaque refresh/email tokens.

Design notes:
 * argon2id for passwords (OWASP-tuned costs).
 * Access tokens: short-lived JWTs. `typ` separates user / learner-device /
   admin tokens so one can never impersonate another.
 * Refresh tokens: random, stored *hashed* (sha256) with rotation + reuse
   detection that kills the whole token family.
 * Email verification / password reset tokens: random, single-use, hashed at
   rest, short TTL. The client never learns whether an account exists.
"""

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from typing import Literal
from uuid import UUID

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from argon2.profiles import RFC_9106_LOW_MEMORY

from .config import get_settings
from .errors import unauthorized

TokenType = Literal["user", "learner", "admin"]

_ph = PasswordHasher.from_parameters(RFC_9106_LOW_MEMORY)


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password: str, hashed: str) -> bool:
    try:
        return _ph.verify(hashed, password)
    except (VerifyMismatchError, InvalidHashError):
        return False


def needs_rehash(hashed: str) -> bool:
    try:
        return _ph.check_needs_rehash(hashed)
    except InvalidHashError:
        return True


def _now() -> datetime:
    return datetime.now(timezone.utc)


def create_access_token(
    subject: UUID | str,
    typ: TokenType,
    *,
    minutes: int | None = None,
    hours: int | None = None,
    learner_id: UUID | str | None = None,
) -> tuple[str, datetime]:
    s = get_settings()
    ttl = timedelta(minutes=minutes or 0, hours=hours or 0) or timedelta(
        minutes=s.access_token_minutes
    )
    exp = _now() + ttl
    claims: dict = {"sub": str(subject), "typ": typ, "aud": s.jwt_audience,
                    "iat": int(_now().timestamp()), "exp": int(exp.timestamp()),
                    "jti": secrets.token_hex(8)}
    if learner_id is not None:
        claims["learner"] = str(learner_id)
    return jwt.encode(claims, s.jwt_secret, algorithm="HS256"), exp


def decode_access_token(token: str, expected_typ: TokenType) -> dict:
    s = get_settings()
    try:
        claims = jwt.decode(token, s.jwt_secret, algorithms=["HS256"], audience=s.jwt_audience)
    except jwt.PyJWTError:
        raise unauthorized("Token is invalid or expired") from None
    if claims.get("typ") != expected_typ:
        raise unauthorized("Wrong token type for this endpoint")
    return claims


def new_opaque_token() -> str:
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> bytes:
    return hashlib.sha256(token.encode()).digest()


def token_matches(token: str, stored_hash: bytes) -> bool:
    return hmac.compare_digest(hash_token(token), stored_hash)


PASSWORD_MIN_LEN = 10
PASSWORD_MAX_LEN = 128


def check_password_policy(password: str) -> str | None:
    """Return a safe, actionable message, or None if acceptable.
    We do not cap complexity beyond length+mixed-class to avoid punishing
    passphrases; breach-list checks belong to the signup UX/email pipeline."""
    if len(password) < PASSWORD_MIN_LEN:
        return f"Password must be at least {PASSWORD_MIN_LEN} characters"
    if len(password) > PASSWORD_MAX_LEN:
        return f"Password must be at most {PASSWORD_MAX_LEN} characters"
    if not (any(c.isalpha() for c in password) and any(c.isdigit() for c in password)):
        return "Password must mix letters and digits"
    return None
