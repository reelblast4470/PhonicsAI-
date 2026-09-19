"""One shared slowapi limiter for the whole app.

Decorators in routers and the middleware in main MUST reference this same
instance — per-module limiters silently lose their route limits.
"""

from slowapi import Limiter
from slowapi.util import get_remote_address

from .config import get_settings

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[get_settings().default_rate_limit],
    headers_enabled=True,
)

# Limit strings are read once at decoration time; keep them in sync here.
AUTH_LIMIT = "8/minute"
LOGIN_LIMIT = "5/minute"
REGISTER_LIMIT = "3/minute"
ADMIN_LOGIN_LIMIT = "5/minute"
FEEDBACK_LIMIT = "6/hour"
TUTOR_LIMIT = "20/minute"
SUPPORT_LIMIT = "4/hour"
