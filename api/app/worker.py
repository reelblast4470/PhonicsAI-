"""Phase 4 background worker.

    python -m app.worker --once            # drain the queue, exit (CI/dev)
    python -m app.worker                   # poll forever (default 3s)
    python -m app.worker --max-jobs 50     # bounded run

Jobs are claimed atomically (`FOR UPDATE SKIP LOCKED`) so several workers can
share one queue; a job whose worker died mid-run stays in 'extracting' until
an admin retries it. Nothing here ever publishes content — the pipeline only
drafts; publishing is a human endpoint.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
from datetime import datetime, timezone

from sqlalchemy import text as sa_text

from .db import get_session_factory
from .ingestion.pipeline import run_job

log = logging.getLogger("phonicsai.worker")


async def claim_next_job():
    """Reserve one queued job; returns its id or None (safe for N workers).
    The real claim happens inside run_job's atomic status flip — this only
    prevents a thundering herd on the same row."""
    factory = get_session_factory()
    async with factory() as db:
        row = (await db.execute(sa_text(
            "SELECT id FROM ai_processing_jobs WHERE status='queued'"
            " ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED"))).first()
        return row[0] if row else None


async def process_once() -> dict | None:
    job_id = await claim_next_job()
    if job_id is None:
        return None
    log.info("worker processing job %s", job_id)
    return await run_job(job_id)


async def main_loop(once: bool, interval: float, max_jobs: int) -> None:
    done = 0
    while True:
        result = await process_once()
        if result is None:
            if once:
                break
            await asyncio.sleep(interval)
            continue
        done += 1
        log.info("job done: %s", result.get("status"))
        if once and done >= max_jobs:
            break
        if not once and done >= max_jobs:
            break


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m app.worker")
    parser.add_argument("--once", action="store_true", help="drain the queue and exit")
    parser.add_argument("--interval", type=float, default=3.0)
    parser.add_argument("--max-jobs", type=int, default=1000)
    args = parser.parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s")
    log.info("phonicsai worker started at %s (provider path: pipeline drafts only)",
             datetime.now(timezone.utc).isoformat())
    try:
        asyncio.run(main_loop(args.once, args.interval, args.max_jobs))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
