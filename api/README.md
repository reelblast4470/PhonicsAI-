# PhonicsAI API — backend foundation

FastAPI + PostgreSQL **modular monolith** (single deployable, no microservices).
Serves the Flutter client under a versioned `/api/v1`; all security-relevant
logic (authorization, XP/streak computation, question grading, rate limiting)
runs server-side. The client never holds a secret.

```
app/
  main.py        create_app(): middleware (CORS, headers, limiter), routers
  config.py      env-driven Settings; refuses dev defaults when ENVIRONMENT=production
  db.py          async engine/session factory (SQLAlchemy 2.0, asyncpg)
  models.py      49 tables: users/parents/learners, content tree, learning ledger,
                 SRS, daily tasks, achievements, assessments, feedback, billing,
                 notifications, admin + audit
  schemas.py     strict request models (extra="forbid") + response models
  security.py    argon2id password hashing, JWT mint/verify (typ: user|learner|admin),
                 hashed opaque refresh/email tokens
  deps.py        auth dependencies incl. parent-ownership + learner-token checks
  errors.py      AppError -> {"error":{"code","message","details"}}; masks 500s
  limiter.py     shared slowapi limiter (per-IP buckets)
  progress.py    deterministic progress engine (ledger -> XP/stars/streak/SRS)
  analytics.py   whitelisted event ingestion (no free-text, no child PII)
  mail.py        outbox/console mail adapters (verify + reset links)
  seed_data.py   small DEV phonics curriculum, origin='seed-dev'
  seed.py        `python -m app.seed` (catalog + optional dev admin)
migrations/      Alembic (async env.py)  — `alembic revision --autogenerate`
ingestion/       Phase-4 pipeline: extract → chunk → AI extract/map/draft →
                 quality gate → proposals (drafts only; publishing is human)
worker.py        `python -m app.worker` — queued-job processor (SKIP LOCKED
                 claims, safe with N workers; --once drains the queue)
tests/           104 pytest tests incl. a full end-to-end journey test, the
                 Phase-4 acceptance suite (upload → publish → learner sees
                 updated content → rollback) and the Phase-5 seam suite
                 (receipts, tutor quota/safety, support queue)
```

## Quickstart (dev)

```bash
cd api
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
# PostgreSQL: create role + databases, then
export DATABASE_URL=postgresql+asyncpg://phonicsai:***@127.0.0.1:5432/phonicsai
.venv/bin/alembic upgrade head
.venv/bin/python -m app.seed            # dev content, marked origin=seed-dev
.venv/bin/uvicorn app.main:app --reload --port 8000
```

Interactive docs: `http://127.0.0.1:8000/docs` (disabled when `ENVIRONMENT=production`).
Health: `GET /healthz` (liveness + DB ping).

Tests: `python3 -m pytest tests -q` (needs a second, disposable
`phonicsai_test` DB — each test truncates and reseeds).

## Auth model

| Token | Who | Lifetime | Notes |
|---|---|---|---|
| access (JWT `typ=user`) | parent | 15 min | HS256, aud=phonicsai-api |
| learner token (`typ=learner`) | one child device | 12 h | minted by the parent (`POST /auth/learner-token`); can only touch its own learner |
| admin token (`typ=admin`) | dashboard logins | 15 min | separate realm — user tokens get 403 on `/admin/*`, admin tokens get 403 everywhere else |
| refresh (opaque) | parent | 30 d | sha256-hashed at rest, rotating; reuse revokes the whole family |

Email verification and password reset use single-use hashed tokens delivered
through the mail adapter (dev = file outbox). Login is allowed before
verification; a reminder flag tells the client. Password reset never reveals
whether an address exists.

**Never trust client ids:** every learner-scoped route re-checks ownership
server-side (`deps.require_parent_owns`), question correctness is decided by
server answer keys, XP/stars/streaks are computed by the progress engine from
the event ledger — replay is neutralized by `client_event_id` dedupe.

## Deployment checklist (production)

1. `ENVIRONMENT=production`; real `JWT_SECRET` (`openssl rand -hex 32`);
   unique strong DB password. The app refuses to boot with dev defaults.
2. TLS at the edge (nginx/Caddy/ALB) — the app is HTTPS-ready but does not
   terminate TLS itself; set `TRUSTED_PROXY_HOPS` only if the proxy *overwrites*
   `X-Forwarded-For` (rate limits key on client IP).
3. `CORS_ORIGINS` limited to the real web origins (mobile flavors don't need CORS).
4. Replace the outbox mail adapter with SES/Postmark + SPF/DKIM.
5. `alembic upgrade head` as a release step, before new code receives traffic
   (migrations are written additive-first: add column → backfill → drop).
6. Remove the dev admin (`admin-dev`) or rotate it. The admin surface
   (`app/routers/admin.py` + `admin_content.py`) covers login, user search/
   disable, feedback triage, subscription grants, publish/unpublish, audit log —
   and the Phase-4 content-intelligence API (sources, jobs, knowledge,
   proposals, conflicts, versions, usage, copilot). A minimal dev console is
   served at `/admin-ui` (disabled in production); the real admin dashboard
   builds on the same endpoints. Run the queue worker separately:
   `python -m app.worker` (systemd unit, not a web dyno).
7. Run under `gunicorn -k uvicorn.workers.UvicornWorker` or equivalent,
   2–4 workers; Postgres pool sized for 100k users on one beefy box first —
   the design scales vertically + read replicas before anything else.
8. Delete endpoint: hard-delete cascades cover learners/progress/analytics;
   backups below define the practical tail.

## Backup strategy

Goal: an RPO of 24 h with plain dumps, ~5 min with WAL archiving; RTO < 1 h.

1. **Nightly logical dumps** — `pg_dump -Fc phonicsai` to object storage
   (S3/GCS with versioning + object lock), encrypted at rest, retained
   **30 daily + 12 monthly**. Example systemd timer + script:

   ```bash
   # /usr/local/bin/phonicsai-backup.sh
   set -euo pipefail
   ts=$(date -u +%F_%H%M)
   pg_dump "$DATABASE_URL_PSQL" -Fc -f "/tmp/phonicsai_$ts.dump"
   rclone copy "/tmp/phonicsai_$ts.dump" remote:phonicsai-backups/ --s3-server-side-encryption AES256
   find /tmp -name 'phonicsai_*.dump' -mtime +7 -delete
   ```

2. **WAL archiving (recommended once real users exist)** — `archive_command`
   pushing WAL segments to the same bucket gives point-in-time recovery
   (`pgBackRest` is the batteries-included option: full + differential chains,
   built-in encryption and S3).

3. **Secrets are backed up separately** — `JWT_SECRET` and DB credentials in
   the deploy platform's secret store (Vault/SSM). Losing the JWT secret only
   invalidates sessions; *rotating* it is the intentional kill switch.

4. **Restore drill** (quarterly, and after any incident):

   ```bash
   createdb phonicsai_restore
   pg_restore -d phonicsai_restore /tmp/phonicsai_<ts>.dump
   pg_dump phonicsai_restore | grep -c "CREATE TABLE"   # expect 50 (49 app
   #   tables + alembic_version — bump the count with every migration)
   ```

   Boot the app against the restored DB and run `pytest tests/test_e2e_flow.py`.

5. **Privacy tail:** account deletion cascades instantly in the live DB;
   nightly dumps keep the rows until rotation expires them (≤ 30 d), so the
   retention promise to parents is "deleted immediately; within 30 days in
   backups." WAL-based PITR gets the same guarantee via key-managed
   encryption per bucket + expiry policies. The analytics ledger stores only
   whitelisted event keys with UUID references — no free text from children.

## Phase 3 — real curriculum & the adaptive loop

* `app/curriculum.py` is the content pipeline: one pure, deterministic
  module → the seeded DB rows (currently **9 modules / 51 lessons / 510 steps
  / 166 questions / 48 phonics patterns / 208 words**; every letter a–z,
  short-vowel word families, blending, segmenting, sh-ch-th-wh-ph, consonant
  blends). It is stamped `origin='seed:curriculum-v1'` and snapshotted into
  `content_versions` (the `/content/curriculum` payload carries that version
  so the client can cache-bust). A CMS later replaces this module; the schema
  and API do not change.
* `GET /api/v1/content/curriculum` — one-shot full tree (steps + questions,
  never the answer key) that backs the Flutter curriculum cache.
* Question engine: `POST …/events` with `question_answered` decides
  correctness from the DB, and now returns a verdict
  (`correct, correct_answer_id, correct_text, explanation, chosen_feedback`)
  that the runner uses for the reveal; XP stays engine-derived and
  `client_event_id` replay-safe.
* Mastery & errors: `GET /learners/{id}/mastery` exposes the
  `learner_skill_progress` rows (attempts, correct, **error_count**, mastery
  0..1, Leitner box, due date) updated by every graded event.
* Adaptive foundation: `GET /learners/{id}/recommendation` implements the
  deterministic rule (placement floor → consolidate-if-accuracy<0.6 → next in
  sequence → due spaced reviews attached); the client Continue card honors it.
* Placement: `placement-english-v2` is now 16 items across five skills; the
  server bands it into `reading_level_key`, which feeds the recommendation
  floor above.
* Client live mode: the Learn flow opens a real session, grades through the
  server, completes authoritatively (stars from the API response), and the
  durable mirror skips lesson finishes for remote-managed lessons (no double
  counting). Profiles created in live/offline-first mode POST to
  `/learners` with an offline pending queue and arm the mirror binding.

## Notes / limits of this foundation

* Production content: the curriculum module is real teaching data but still
  seeded, not CMS-authored; audio rows are placeholder paths until the media
  pipeline fills them.
* Subscription receipts from stores are recorded but *unverified* until a
  server-side receipt check is wired; entitlements flip only via admin grants
  or verified receipts (`commerce.py`).
* Rate limiting is per-process in-memory (multi-worker = multiplied budget);
  point `Limiter` at Redis storage before horizontal scaling.

## Phase 4 — AI content-intelligence pipeline

Admins upload educational resources (PDF/DOCX/EPUB/TXT, paste, or a plain-text
URL) with mandatory title/author/age/level/language/**license** metadata. The
pipeline: extract → chunk (500–1000 tokens, page/chapter refs kept) → AI
knowledge extraction + classification (12 categories) → comparison against the
live curriculum (duplicate / improve / missing / **conflict**) → draft proposals
(lessons, questions, improvement diffs) → deterministic quality gate. Then it
**stops**: proposals are `draft → ai_reviewed → human_review → approved →
published`; only the human-triggered publish endpoint mutates curriculum, and
it snapshots before/after into `content_versions` so every change is diffable
and exactly rollbackable.

Hard guarantees (all under test):

* AI never publishes; publishing requires `status='approved'`.
* Two sources that disagree produce a conflict report, never a chosen winner;
  conflicted knowledge cannot generate proposals.
* The quality gate blocks (not review-flags): invalid answer keys (exactly one
  correct), duplicate questions (prompt+options vs the live bank), blank or
  identical options, unsafe words, and **>=20 consecutive words reproduced
  verbatim from a source** (copyright guard).
* Every provider call — including the offline `mock` provider, and failures —
  is metered in `ai_usage_logs` (tokens, latency, estimated USD) surfaced at
  `/admin/content/usage`.
* Uploads are size-capped, magic-byte-checked, zip-bomb-guarded, stored off
  the web root, readable only through an admin route; deleting a source
  removes its bytes.
* Providers are pluggable (`AI_PROVIDER=mock|gemini|openai_compatible`); keys
  live in the backend env. `python -m app.worker` processes the queue; the
  inline admin "run now" endpoint is the dev path.
* Retrieval: knowledge/chunks are searchable (`/admin/content/search`) with
  provider embeddings when available (the mock ships a deterministic
  hashed-BoW embedder); pgvector remains the swap-in, not a dependency.

Known limits of this phase: extraction is *basic* (born-digital PDFs; scanned
PDFs/images flag `ocr_needed` until an `OCR_COMMAND` hook is configured); the
mock provider is a rule engine, not an LLM — swap `AI_PROVIDER` for real
generation, the flow is identical; long books process head-first under the
per-job chunk budget (documented in doc `notes`); the admin *product* UI is a
dev console, not the final dashboard.

## Phase 5 — the last marked seams, closed

**AI tutor** (`routers/tutor.py`): `POST /learners/{id}/tutor/reply` (SSE by
default, `?sse=false` for JSON) and `GET .../starters`. The learner's context
(name, age, level, struggling sounds) is derived server-side from rows we
already have — the request carries only the child's message. A child-safety
policy runs *before* the model (blocked-topic patterns get a deterministic
kind redirect); off-topic model answers come back `flagged`, stored in
`tutor_exchanges` and reviewable at `/admin/tutor/exchanges?flagged_only=true`
— flags feed the parent's "redirected N times" report, never a punishment.
Free accounts get `TUTOR_FREE_DAILY_MESSAGES` questions/day counted here; a
**server-verified** Plus subscription (not a client event report) lifts it.
The Flutter adapter (`features/tutor/data/api_tutor_service.dart`) switches
itself in once a profile is bound; the local rule engine keeps answering,
honestly labelled, whenever it is not.

**Receipt verification** (`app/billing.py`): `POST /subscriptions/me/receipt`
is the only endpoint that flips entitlements. `BILLING_MODE=mock` (dev/test;
boot-refused in production), `google_play` (androidpublisher REST, ops-minted
OAuth token), `app_store` (verifyReceipt, sandbox auto-fallback), or `off`
(honest 503). Verified store transactions land in `verified_receipts` with a
unique (store, transaction_id) — the replay lock: same receipt, second
account → 409. Client-reported events keep their reconciliation-only role.

**Support intake** (`routers/support.py`): `POST /support/tickets` (the path
the app already targeted), parent-visible thread + notification on reply,
admin queue at `/admin/support/tickets` with audit on every change. The
`support` admin role may answer tickets in this domain (that *is* its job)
while remaining read-only for content.

Tables 46→49 (`tutor_exchanges`, `verified_receipts`, `support_tickets`),
migration `1100e928bded` (additive, reversible). Tutor exchanges carry a
documented 30-day retention expectation swept at deploy time.

Known limits: SSE is produced server-side but the Flutter app consumes the
JSON form (token-by-token rendering is polish, the wire format is final);
store verifiers are real REST calls behind config and only exercised against
the mock verifier here — Play/App Store credentials must be wired at deploy;
the tutor works on the offline mock rule engine until real `AI_*` keys land.
