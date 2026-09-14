"""Email outbox.

'outbox' mode writes .eml files to disk — the dev/test stand-in that keeps
verification/reset flows *real* (tokens issued, single-use, expiring) without
any provider. Swap the send() implementation for SES/Postmark/SMTP in
production; nothing else changes.
"""

import logging
import re
from datetime import datetime, timezone
from pathlib import Path

from .config import get_settings

log = logging.getLogger("phonicsai.mail")


def send_email(*, to: str, subject: str, body: str) -> None:
    s = get_settings()
    safe_to = re.sub(r"[^a-zA-Z0-9@._+-]", "_", to)  # never trust input for paths
    if s.mail_mode == "console":
        log.info("[mail] to=%s subject=%s\n%s", to, subject, body)
        return
    out = Path(s.outbox_dir)
    out.mkdir(parents=True, exist_ok=True)
    fname = out / f"{datetime.now(timezone.utc):%Y%m%dT%H%M%S_%f}_{safe_to}.eml"
    fname.write_text(
        f"From: no-reply@phonicsai.local\nTo: {to}\n"
        f"Subject: {subject}\nDate: {datetime.now(timezone.utc):%a, %d %b %Y %H:%M:%S +0000}\n"
        f"\n{body}\n",
        encoding="utf-8",
    )


def latest_email_for(to: str) -> str | None:
    """Test helper: newest outbox mail body for an address."""
    s = get_settings()
    out = Path(s.outbox_dir)
    if not out.exists():
        return None
    safe_to = re.sub(r"[^a-zA-Z0-9@._+-]", "_", to)
    files = sorted(out.glob(f"*_{safe_to}.eml"))
    return files[-1].read_text(encoding="utf-8") if files else None
