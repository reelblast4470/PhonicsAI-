"""Phase 4 admin router: the content-intelligence pipeline's whole surface.

Everything here lives in the admin realm: `/admin/content/*` requires an admin
token (role 'editor' or 'super' for writes), user/learner tokens get 403.
Source files are only ever readable through an admin route. Every mutation is
audited. AI never publishes: publish requires status='approved' (a human set
it), and publishing snapshots the previous state first.
"""

from __future__ import annotations

import hashlib
import logging
import re
import uuid as uuidlib
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, File, Form, Query, Request, Response, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import func, or_, select, text as sa_text

from ..config import get_settings
from ..deps import Admin, DbSession
from ..errors import AppError, forbidden, not_found
from ..ingestion import pipeline
from ..ingestion.ai import get_ai_service
from ..ingestion.extract import ALL_EXT, check_size, sniff_kind
from ..ingestion.quality import norm_prompt, validate_proposal
from ..models import (
    AiProcessingJob,
    AiUsageLog,
    ContentConflict,
    ContentProposal,
    ContentReview,
    ContentSource,
    ContentVersion,
    KnowledgeItem,
    KnowledgeSource,
    Lesson,
    SourceChunk,
    SourceDocument,
)
from ..schemas import (
    CopilotIn, CopilotOut, ConflictOut, ConflictResolveIn, DocumentOut,
    JobOut, KnowledgeOut, PasteIn, ProposalDetailOut, ProposalEditIn,
    ProposalOut, ReviewActionIn, SourceOut, UrlIn,
)
from .admin import _audit

log = logging.getLogger("phonicsai.admin_content")
router = APIRouter(prefix="/admin/content", tags=["admin-content"])

LICENSES = {"self_owned", "licensed", "public_domain", "permission_granted",
            "unknown"}
EDITOR_ROLES = ("super", "editor")


def _require_editor(admin) -> None:
    if admin.role not in EDITOR_ROLES:
        raise forbidden("Your admin role cannot change content")


def _bad(msg: str, code: str = "validation_failed") -> AppError:
    return AppError(code, msg, 422)


def _validate_meta(meta: dict) -> dict:
    lic = (meta.get("license_type") or "").strip()
    if lic not in LICENSES:
        raise _bad("license_type is required: one of " + ", ".join(sorted(LICENSES)),
                   "license_required")
    if meta.get("target_age_min") and meta.get("target_age_max"):
        if int(meta["target_age_min"]) > int(meta["target_age_max"]):
            raise _bad("target_age_min is greater than target_age_max")
    title = (meta.get("title") or "").strip()
    if not 2 <= len(title) <= 200:
        raise _bad("title must be 2-200 characters")
    meta = dict(meta, title=title)
    return meta


async def _store_payload(meta: dict, *, kind: str, filename: str, raw: bytes,
                         admin, db) -> tuple[ContentSource, SourceDocument]:
    """Dedupe by sha256; store under uploads_dir/<hash2>/<uuid>.<ext>."""
    s = get_settings()
    digest = hashlib.sha256(raw).hexdigest()
    ext = Path(filename).suffix.lower()
    root = Path(s.uploads_dir)
    rel_dir = digest[:2]
    (root / rel_dir).mkdir(parents=True, exist_ok=True)
    stored = root / rel_dir / f"{uuidlib.uuid4()}{ext}"
    stored.write_bytes(raw)
    source = ContentSource(
        title=meta["title"], author=meta.get("author"),
        publisher=meta.get("publisher"), description=meta.get("description"),
        category=meta.get("category") or "phonics",
        target_age_min=meta.get("target_age_min"),
        target_age_max=meta.get("target_age_max"),
        target_level_key=meta.get("target_level_key"),
        language=meta.get("language") or "en",
        license_type=meta["license_type"], license_notes=meta.get("license_notes"),
        status="intake", added_by_admin_id=admin.id)
    db.add(source)
    await db.flush()
    doc = SourceDocument(
        source_id=source.id, kind=kind, filename=filename,
        media_type=meta.get("media_type"), byte_size=len(raw), sha256=digest,
        storage_path=str(stored.relative_to(root)), extraction_status="pending")
    db.add(doc)
    await db.flush()
    return source, doc


async def _enqueue(db, source: ContentSource, admin) -> AiProcessingJob:
    job = AiProcessingJob(source_id=source.id, status="queued",
                          job_type="process_document",
                          requested_by_admin_id=admin.id)
    db.add(job)
    await db.flush()
    return job


def _meta_form(**pairs) -> dict:  # small helper for multipart field grouping
    return {k: v for k, v in pairs.items() if v not in (None, "")}


# ===========================================================================
# sources
# ===========================================================================
@router.post("/sources", response_model=SourceOut, status_code=201)
async def upload_source(
    request: Request, db: DbSession, admin: Admin,
    file: Annotated[UploadFile, File()],
    title: Annotated[str, Form()],
    license_type: Annotated[str, Form()],
    author: Annotated[str | None, Form()] = None,
    publisher: Annotated[str | None, Form()] = None,
    description: Annotated[str | None, Form()] = None,
    category: Annotated[str | None, Form()] = None,
    target_age_min: Annotated[int | None, Form()] = None,
    target_age_max: Annotated[int | None, Form()] = None,
    target_level_key: Annotated[str | None, Form()] = None,
    language: Annotated[str | None, Form()] = None,
    license_notes: Annotated[str | None, Form()] = None,
):
    """Multipart upload + mandatory metadata/licence. Returns immediately
    with a queued job — processing never blocks the request."""
    _require_editor(admin)
    filename = (file.filename or "upload.bin")[:200]
    if Path(filename).suffix.lower() not in ALL_EXT:
        raise _bad("unsupported file type — allowed: " + ", ".join(sorted(ALL_EXT)),
                   "unsupported_file_type")
    raw = await file.read()
    s = get_settings()
    if len(raw) > s.upload_max_mb * 1024 * 1024:
        raise AppError("file_too_large",
                       f"max {s.upload_max_mb} MB per source document", 413)
    if not raw:
        raise _bad("empty file")
    try:
        ext = sniff_kind(filename, raw)
    except ValueError as exc:
        raise _bad(str(exc), "invalid_file")
    meta = _validate_meta(_meta_form(
        title=title, author=author, publisher=publisher, description=description,
        category=category, target_age_min=target_age_min,
        target_age_max=target_age_max, target_level_key=target_level_key,
        language=language, license_type=license_type, license_notes=license_notes))
    meta["media_type"] = file.content_type or "application/octet-stream"
    source, doc = await _store_payload(meta, kind="file", filename=filename,
                                       raw=raw, admin=admin, db=db)
    job = await _enqueue(db, source, admin)
    await _audit(db, admin, "content.source_upload", entity_type="content_source",
                 entity_id=source.id, after={"title": meta["title"], "sha256": doc.sha256,
                                             "license": meta["license_type"]},
                 request=request)
    return _source_out(source, [doc], [job])


@router.post("/sources/paste", response_model=SourceOut, status_code=201)
async def paste_source(body: PasteIn, request: Request, db: DbSession, admin: Admin):
    """Copy-paste text intake (also great for testing with small documents)."""
    _require_editor(admin)
    meta = _validate_meta(body.model_dump(exclude={"text"}))
    raw = body.text.encode()
    if len(raw) > get_settings().upload_max_mb * 1024 * 1024:
        raise AppError("file_too_large", "pasted text exceeds the size cap", 413)
    source, doc = await _store_payload(meta, kind="paste",
                                       filename=f"{uuidlib.uuid4().hex[:8]}.txt",
                                       raw=raw, admin=admin, db=db)
    doc.media_type = "text/plain"
    job = await _enqueue(db, source, admin)
    await _audit(db, admin, "content.source_paste", entity_type="content_source",
                 entity_id=source.id, after={"title": meta["title"]}, request=request)
    return _source_out(source, [doc], [job])


@router.post("/sources/url", response_model=SourceOut, status_code=201)
async def fetch_url(body: UrlIn, request: Request, db: DbSession, admin: Admin):
    """Fetch a plain-text/markdown URL server-side (SSRF-guarded: http/https
    only, size-capped, content-type allowlist, no redirects to other schemes)."""
    _require_editor(admin)
    import httpx
    meta = _validate_meta(body.model_dump(exclude={"url", "max_bytes"}))
    url = meta.pop("url", body.url)
    if not re.match(r"^https?://", url):
        raise _bad("only http(s) urls are allowed", "invalid_url")
    try:
        async with httpx.AsyncClient(timeout=60, follow_redirects=True, max_redirects=5) as c:
            r = await c.get(url, headers={"User-Agent": "phonicsai-admin/1"})
    except httpx.HTTPError:
        raise AppError("url_fetch_failed", "could not fetch that url", 502)
    if r.status_code != 200:
        raise AppError("url_fetch_failed", f"remote returned {r.status_code}", 502)
    ctype = r.headers.get("content-type", "").split(";")[0].strip().lower()
    if ctype not in ("text/plain", "text/markdown", "text/x-markdown"):
        raise AppError("unsupported_content_type",
                       f"only text/plain or text/markdown urls are accepted "
                       f"(got {ctype or 'unknown'})", 415)
    raw = r.content[: body.max_bytes]
    meta["media_type"] = ctype
    source, doc = await _store_payload(meta, kind="url", filename="webpage.txt",
                                       raw=raw, admin=admin, db=db)
    job = await _enqueue(db, source, admin)
    await _audit(db, admin, "content.source_url", entity_type="content_source",
                 entity_id=source.id, after={"title": meta["title"], "url": url},
                 request=request)
    return _source_out(source, [doc], [job])


@router.get("/sources", response_model=list[SourceOut])
async def list_sources(db: DbSession, admin: Admin,
                       status: str | None = Query(default=None)):
    rows = list(await db.scalars(select(ContentSource).order_by(
        ContentSource.created_at.desc()).limit(200)))
    out = []
    for src in rows:
        docs = list(await db.scalars(select(SourceDocument).where(
            SourceDocument.source_id == src.id)))
        jobs = list(await db.scalars(select(AiProcessingJob).where(
            AiProcessingJob.source_id == src.id).order_by(
            AiProcessingJob.created_at.desc()).limit(5)))
        if status and src.status != status:
            continue
        out.append(_source_out(src, docs, jobs))
    return out


@router.get("/sources/{source_id}", response_model=SourceOut)
async def get_source(source_id: UUID, db: DbSession, admin: Admin):
    src = await db.get(ContentSource, source_id)
    if src is None:
        raise not_found("Source not found")
    docs = list(await db.scalars(select(SourceDocument).where(
        SourceDocument.source_id == src.id).order_by(SourceDocument.created_at)))
    jobs = list(await db.scalars(select(AiProcessingJob).where(
        AiProcessingJob.source_id == src.id).order_by(
        AiProcessingJob.created_at.desc()).limit(10)))
    return _source_out(src, docs, jobs)


@router.post("/sources/{source_id}/process", response_model=dict)
async def process_source_now(source_id: UUID, request: Request, db: DbSession,
                             admin: Admin):
    """Inline processing for dev/testing (the production path is the worker).
    Runs the newest queued/failed job synchronously and returns its stats."""
    _require_editor(admin)
    latest = await db.scalar(select(AiProcessingJob).where(
        AiProcessingJob.source_id == source_id).order_by(
        AiProcessingJob.created_at.desc()).limit(1))
    if latest is None:
        raise not_found("Source has no processing job")
    if latest.status == "completed":
        raise AppError("already_finished", "this source's job is already completed", 409)
    if latest.status not in ("queued", "failed", "needs_review"):
        raise AppError("job_busy", f"job is {latest.status}", 409)
    job_id = latest.id
    await db.commit()
    try:
        result = await pipeline.run_job(job_id)
    except (LookupError, RuntimeError) as exc:
        raise AppError("job_busy" if "job_busy" in str(exc) else "job_failed",
                       str(exc), 409)
    await _audit(db, admin, "content.source_process", entity_type="content_source",
                 entity_id=source_id, after=result, request=request)
    return {"job_id": str(job_id), **result}


@router.get("/sources/{source_id}/documents/{document_id}/download")
async def download_document(source_id: UUID, document_id: UUID, db: DbSession,
                            admin: Admin):
    """Admin-only raw access. Source bytes are never served elsewhere."""
    doc = await db.get(SourceDocument, document_id)
    if doc is None or doc.source_id != source_id:
        raise not_found("Document not found")
    path = Path(get_settings().uploads_dir) / doc.storage_path
    if not path.exists():
        raise not_found("Stored file is missing")
    return FileResponse(path, media_type=doc.media_type or "application/octet-stream",
                        filename=doc.filename, headers={"Content-Disposition":
                                                         f'attachment; filename="{doc.filename}"'})


@router.get("/sources/{source_id}/documents/{document_id}/chunks", response_model=list[dict])
async def list_chunks(source_id: UUID, document_id: UUID, db: DbSession, admin: Admin,
                      limit: int = Query(default=50, ge=1, le=500)):
    """Admin chunk browser: what the retrieval index actually holds."""
    doc = await db.get(SourceDocument, document_id)
    if doc is None or doc.source_id != source_id:
        raise not_found("Document not found")
    return [{"position": c.position, "page_start": c.page_start, "page_end": c.page_end,
             "chapter_ref": c.chapter_ref, "token_estimate": c.token_estimate,
             "has_embedding": c.embedding is not None,
             "preview": c.text[:200]}
            for c in await db.scalars(select(SourceChunk).where(
                SourceChunk.document_id == doc.id).order_by(
                SourceChunk.position).limit(limit))]


@router.delete("/sources/{source_id}", status_code=204)
async def delete_source(source_id: UUID, request: Request, db: DbSession, admin: Admin):
    _require_editor(admin)
    src = await db.get(ContentSource, source_id)
    if src is None:
        raise not_found("Source not found")
    docs = list(await db.scalars(select(SourceDocument).where(
        SourceDocument.source_id == src.id)))
    before = {"title": src.title}
    await db.delete(src)
    await db.flush()
    # stored bytes are removed too — deletion must be real (privacy hygiene)
    for doc in docs:
        p = Path(get_settings().uploads_dir) / doc.storage_path
        p.unlink(missing_ok=True)
    await _audit(db, admin, "content.source_delete", entity_type="content_source",
                 entity_id=source_id, before=before, request=request)
    return Response(status_code=204)


def _source_out(src: ContentSource, docs, jobs) -> dict:
    return {
        "id": src.id, "title": src.title, "author": src.author,
        "publisher": src.publisher, "category": src.category,
        "description": src.description, "target_age_min": src.target_age_min,
        "target_age_max": src.target_age_max, "target_level_key": src.target_level_key,
        "language": src.language, "license_type": src.license_type,
        "license_notes": src.license_notes, "status": src.status,
        "created_at": src.created_at,
        "documents": [DocumentOut.model_validate(d).model_dump() for d in docs],
        "jobs": [JobOut.model_validate(j).model_dump() for j in jobs],
    }


# ===========================================================================
# jobs
# ===========================================================================
@router.get("/jobs", response_model=list[JobOut])
async def list_jobs(db: DbSession, admin: Admin, status: str | None = None,
                    source_id: UUID | None = None):
    q = select(AiProcessingJob).order_by(AiProcessingJob.created_at.desc()).limit(200)
    if status:
        q = q.where(AiProcessingJob.status == status)
    if source_id:
        q = q.where(AiProcessingJob.source_id == source_id)
    return list(await db.scalars(q))


@router.post("/jobs/{job_id}/run", response_model=dict)
async def run_job_now(job_id: UUID, request: Request, db: DbSession, admin: Admin):
    _require_editor(admin)
    job = await db.get(AiProcessingJob, job_id)
    if job is None:
        raise not_found("Job not found")
    if job.status == "completed":
        raise AppError("already_finished", "job is already completed", 409)
    await db.commit()
    try:
        result = await pipeline.run_job(job_id)
    except (LookupError, RuntimeError) as exc:
        raise AppError("job_busy" if "job_busy" in str(exc) else "job_failed",
                       str(exc), 409)
    await _audit(db, admin, "content.job_run", entity_type="ai_processing_job",
                 entity_id=job_id, after=result, request=request)
    return {"job_id": str(job_id), **result}


@router.post("/jobs/{job_id}/retry", response_model=JobOut)
async def retry_job(job_id: UUID, request: Request, db: DbSession, admin: Admin):
    """Safe retry: a failed job returns to 'queued' (attempts preserved for
    visibility); the worker or /run picks it up again."""
    _require_editor(admin)
    job = await db.get(AiProcessingJob, job_id)
    if job is None:
        raise not_found("Job not found")
    # 'extracting' is retryable too: it only happens if a worker died mid-run,
    # and admin-retry is the documented recovery path (the live claim in
    # run_job stays strict, so this can never double-run a healthy job).
    if job.status not in ("failed", "needs_review", "extracting"):
        raise AppError("not_retryable", f"job is {job.status}; only failed or "
                                        "needs-review jobs can be retried", 409)
    before = {"status": job.status, "error": job.error}
    job.status = "queued"
    job.error = None
    job.stage_note = "retried by admin"
    await _audit(db, admin, "content.job_retry", entity_type="ai_processing_job",
                 entity_id=job_id, before=before, after={"status": "queued"},
                 request=request)
    return job


# ===========================================================================
# knowledge base
# ===========================================================================
@router.get("/knowledge", response_model=list[KnowledgeOut])
async def list_knowledge(db: DbSession, admin: Admin,
                         category: str | None = None, q: str | None = None,
                         min_confidence: float | None = None,
                         status: str | None = None,
                         source_id: UUID | None = None):
    query = select(KnowledgeItem).order_by(
        KnowledgeItem.confidence.desc(), KnowledgeItem.created_at.desc()).limit(200)
    if source_id:
        query = query.where(KnowledgeItem.source_id == source_id)
    if category:
        query = query.where(KnowledgeItem.category == category)
    if status:
        query = query.where(KnowledgeItem.status == status)
    if min_confidence is not None:
        query = query.where(KnowledgeItem.confidence >= min_confidence)
    if q:
        like = f"%{q}%"
        query = query.where(or_(KnowledgeItem.title.ilike(like),
                                 KnowledgeItem.body.ilike(like),
                                 KnowledgeItem.topic_key.ilike(like)))
    out = []
    for k in await db.scalars(query):
        out.append(await _knowledge_out(db, k))
    return out


@router.get("/knowledge/{item_id}", response_model=KnowledgeOut)
async def get_knowledge(item_id: UUID, db: DbSession, admin: Admin):
    k = await db.get(KnowledgeItem, item_id)
    if k is None:
        raise not_found("Knowledge item not found")
    return await _knowledge_out(db, k)


@router.patch("/knowledge/{item_id}", response_model=KnowledgeOut)
async def patch_knowledge(item_id: UUID, request: Request, db: DbSession, admin: Admin,
                          status: str = Query(...)):
    _require_editor(admin)
    if status not in ("new", "mapped", "discarded"):
        raise _bad("status must be new|mapped|discarded")
    k = await db.get(KnowledgeItem, item_id)
    if k is None:
        raise not_found("Knowledge item not found")
    before = {"status": k.status}
    k.status = status
    await _audit(db, admin, "content.knowledge_status", entity_type="knowledge_item",
                 entity_id=item_id, before=before, after={"status": status},
                 request=request)
    return await _knowledge_out(db, k)


async def _knowledge_out(db, k: KnowledgeItem) -> dict:
    evidence = list(await db.scalars(select(KnowledgeSource).where(
        KnowledgeSource.knowledge_item_id == k.id)))
    return {
        "id": k.id, "source_id": k.source_id, "category": k.category,
        "title": k.title, "body": k.body, "topic_key": k.topic_key,
        "skill_key": k.skill_key, "confidence": k.confidence,
        "provenance": k.provenance, "status": k.status, "ai_model": k.ai_model,
        "created_at": k.created_at,
        "evidence": [{"document_id": str(e.document_id) if e.document_id else None,
                      "page": e.page_ref, "chapter": e.chapter_ref,
                      "snippet": e.snippet} for e in evidence],
    }


# ===========================================================================
# proposals + approval workflow
# ===========================================================================
@router.get("/proposals", response_model=list[ProposalOut])
async def list_proposals(db: DbSession, admin: Admin, status: str | None = None,
                         action: str | None = None, source_id: UUID | None = None):
    q = select(ContentProposal).order_by(ContentProposal.created_at.desc()).limit(200)
    if status:
        q = q.where(ContentProposal.status == status)
    if action:
        q = q.where(ContentProposal.action == action)
    if source_id:
        q = q.where(ContentProposal.source_id == source_id)
    return list(await db.scalars(q))


@router.get("/proposals/{proposal_id}", response_model=ProposalDetailOut)
async def get_proposal(proposal_id: UUID, db: DbSession, admin: Admin):
    p = await db.get(ContentProposal, proposal_id)
    if p is None:
        raise not_found("Proposal not found")
    side = None
    if p.target_entity_id is not None and p.action in ("improve_lesson",
                                                       "new_questions"):
        lesson = await db.get(Lesson, p.target_entity_id)
        if lesson is not None:
            side = {
                "current": await pipeline.dump_lesson_snapshot(db, lesson),
                "proposed": p.payload,
            }
    reviews = [{"action": r.action, "notes": r.notes,
                "at": r.created_at.isoformat(),
                "admin_id": str(r.admin_id) if r.admin_id else None}
               for r in await db.scalars(select(ContentReview).where(
                   ContentReview.proposal_id == p.id).order_by(ContentReview.created_at))]
    out = ProposalOut.model_validate(p).model_dump()
    out.update({"payload": p.payload, "knowledge_item_ids": p.knowledge_item_ids or [],
                "reviews": reviews, "side_by_side": side,
                "license": (await db.get(ContentSource, p.source_id)).license_type
                if p.source_id else None})
    return out


@router.patch("/proposals/{proposal_id}", response_model=ProposalDetailOut)
async def edit_proposal(proposal_id: UUID, body: ProposalEditIn, request: Request,
                        db: DbSession, admin: Admin):
    """Human edits. Re-runs the deterministic quality gate — editing content
    can never skip validation."""
    _require_editor(admin)
    p = await db.get(ContentProposal, proposal_id)
    if p is None:
        raise not_found("Proposal not found")
    if p.status not in ("draft", "ai_reviewed", "human_review"):
        raise AppError("not_editable", f"proposals in status {p.status} cannot be "
                                       "edited", 409)
    if body.payload is not None:
        p.payload = body.payload
    if body.summary is not None:
        p.summary = body.summary[:110]
    if body.target_code is not None:
        lesson = await db.scalar(select(Lesson).where(Lesson.code == body.target_code))
        p.target_code = body.target_code
        p.target_entity_id = lesson.id if lesson else None
        p.target_entity_type = "lesson" if lesson else None
    items = [ {"confidence": 0.7, "topic_key": None, "target_age_min": 3} ]
    if p.knowledge_item_ids:
        rows = list(await db.scalars(select(KnowledgeItem).where(
            KnowledgeItem.id.in_([uuidlib.UUID(str(x)) for x in p.knowledge_item_ids]))))
        items = [{"confidence": r.confidence, "topic_key": r.topic_key,
                  "target_age_min": r.target_age_min or 3} for r in rows] or items
    chunk_texts = []
    if p.source_id:
        doc_ids = select(SourceDocument.id).where(
            SourceDocument.source_id == p.source_id)
        chunk_texts = [c.text for c in await db.scalars(
            select(SourceChunk).where(SourceChunk.document_id.in_(doc_ids)))]
    target_lesson = (await db.get(Lesson, p.target_entity_id)) if p.target_entity_id else None
    validation = validate_proposal(
        p.payload or {}, action=p.action, items=items,
        existing_prompts=await pipeline.existing_prompts(db),
        chunk_texts=chunk_texts,
        target_lesson=({"id": target_lesson.id, "code": target_lesson.code,
                        "title": target_lesson.title, "teach": []}
                       if target_lesson else None))
    before = {"status": p.status, "validation": p.validation}
    p.validation = validation
    p.status = "ai_reviewed" if validation["passed"] else "human_review"
    p.edit_count += 1
    db.add(ContentReview(proposal_id=p.id, admin_id=admin.id, action="edited",
                         notes=body.notes))
    await _audit(db, admin, "content.proposal_edit", entity_type="content_proposal",
                 entity_id=p.id, before=before, after={"status": p.status},
                 request=request)
    await db.flush()
    return await get_proposal(p.id, db, admin)


@router.post("/proposals/{proposal_id}/approve", response_model=ProposalOut)
async def approve_proposal(proposal_id: UUID, body: ReviewActionIn, request: Request,
                           db: DbSession, admin: Admin):
    _require_editor(admin)
    p = await db.get(ContentProposal, proposal_id)
    if p is None:
        raise not_found("Proposal not found")
    if p.status not in ("ai_reviewed", "human_review"):
        raise AppError("not_approvable", f"status is {p.status}", 409)
    if p.validation and not p.validation.get("passed") and not body.force:
        raise AppError("validation_failed", "the quality gate still reports block "
                                            "flags — edit the draft first", 409)
    p.status = "approved"
    p.approved_by_admin_id = admin.id
    p.approved_at = datetime.now(timezone.utc)
    db.add(ContentReview(proposal_id=p.id, admin_id=admin.id, action="approved",
                         notes=body.notes))
    await _audit(db, admin, "content.proposal_approve", entity_type="content_proposal",
                 entity_id=p.id, after={"status": "approved"}, request=request)
    return p


@router.post("/proposals/{proposal_id}/reject", response_model=ProposalOut)
async def reject_proposal(proposal_id: UUID, body: ReviewActionIn, request: Request,
                          db: DbSession, admin: Admin):
    _require_editor(admin)
    p = await db.get(ContentProposal, proposal_id)
    if p is None:
        raise not_found("Proposal not found")
    if p.status not in ("draft", "ai_reviewed", "human_review", "approved"):
        raise AppError("not_rejectable", f"status is {p.status}", 409)
    p.status = "rejected"
    db.add(ContentReview(proposal_id=p.id, admin_id=admin.id, action="rejected",
                         notes=body.notes))
    await _audit(db, admin, "content.proposal_reject", entity_type="content_proposal",
                 entity_id=p.id, after={"status": "rejected"}, request=request)
    return p


@router.post("/proposals/{proposal_id}/regenerate", response_model=ProposalOut)
async def regenerate_proposal(proposal_id: UUID, request: Request, db: DbSession,
                              admin: Admin):
    """'Request regeneration' — re-drafts from the same knowledge item; the
    previous draft survives in the version/audit history."""
    _require_editor(admin)
    p = await db.get(ContentProposal, proposal_id)
    if p is None:
        raise not_found("Proposal not found")
    if p.status in ("published", "rolled_back"):
        raise AppError("not_regenerable", "published proposals are not regenerated; "
                                          "roll back first", 409)
    item_id = (p.knowledge_item_ids or [None])[0]
    k = await db.get(KnowledgeItem, uuidlib.UUID(str(item_id))) if item_id else None
    if k is None:
        raise _bad("this proposal has no knowledge item to regenerate from")
    curriculum = await pipeline.curriculum_snapshot(db)
    words = await _word_bank(db)
    provider = get_ai_service()
    draft = await provider.generate_draft(
        {"id": str(k.id), "category": k.category, "title": k.title, "body": k.body,
         "topic_key": k.topic_key, "confidence": k.confidence},
        {"action": p.action if p.action != "new_questions" else "improve_lesson",
         "words": words, "phonemes": curriculum["patterns"], "n_questions": 5,
         "admin_id": admin.id})
    target = (await db.get(Lesson, p.target_entity_id)) if p.target_entity_id else None
    validation = validate_proposal(
        draft.get("payload") or {}, action=p.action,
        items=[{"confidence": k.confidence, "topic_key": k.topic_key,
                "target_age_min": k.target_age_min or 3}],
        existing_prompts=await pipeline.existing_prompts(db),
        chunk_texts=[], target_lesson=({"id": target.id, "code": target.code,
                                       "title": target.title, "teach": []}
                                      if target else None))
    p.payload = draft.get("payload") or {}
    p.validation = validation
    p.status = "ai_reviewed" if validation["passed"] else "human_review"
    db.add(ContentReview(proposal_id=p.id, admin_id=admin.id, action="regenerated",
                         notes=None))
    await _audit(db, admin, "content.proposal_regenerate",
                 entity_type="content_proposal", entity_id=p.id, request=request)
    return p


async def _word_bank(db) -> list[dict]:
    from ..models import PhonicsPattern, Word
    out = []
    for w in await db.scalars(select(Word).order_by(func.random()).limit(24)):
        decomp = []
        for pid in (w.pattern_ids or []):
            try:
                pat = await db.get(PhonicsPattern, uuidlib.UUID(str(pid)))
            except ValueError:
                continue
            if pat:
                decomp.append(pat.grapheme.lower())
        out.append({"text": w.text, "decomp": decomp})
    return out


@router.post("/proposals/{proposal_id}/publish", response_model=dict)
async def publish_proposal(proposal_id: UUID, body: ReviewActionIn, request: Request,
                           db: DbSession, admin: Admin):
    _require_editor(admin)
    p = await db.get(ContentProposal, proposal_id)
    if p is None:
        raise not_found("Proposal not found")
    if p.status != "approved":
        raise AppError("not_approved",
                       "only an APPROVED proposal can be published — the AI never "
                       "publishes on its own", 409)
    await db.commit()  # end the read txn; publish manages its own writes below
    try:
        result = await pipeline.publish_proposal(db, p, admin, reason=body.notes)
    except RuntimeError as exc:
        raise AppError("publish_failed", str(exc), 409)
    await _audit(db, admin, "content.proposal_publish", entity_type="content_proposal",
                 entity_id=p.id, after=result, request=request)
    return result


@router.post("/proposals/{proposal_id}/rollback", response_model=dict)
async def rollback_proposal(proposal_id: UUID, request: Request, db: DbSession,
                            admin: Admin):
    _require_editor(admin)
    p = await db.get(ContentProposal, proposal_id)
    if p is None:
        raise not_found("Proposal not found")
    if p.status != "published":
        raise AppError("not_published", "only published proposals can be rolled back",
                       409)
    await db.commit()
    try:
        result = await pipeline.rollback_proposal(db, p, admin)
    except RuntimeError as exc:
        raise AppError("rollback_failed", str(exc), 409)
    await _audit(db, admin, "content.proposal_rollback", entity_type="content_proposal",
                 entity_id=p.id, after=result, request=request)
    return result


# ===========================================================================
# conflicts, versions, usage, copilot, search
# ===========================================================================
@router.get("/conflicts", response_model=list[ConflictOut])
async def list_conflicts(db: DbSession, admin: Admin,
                         status: str = Query(default="open")):
    return list(await db.scalars(select(ContentConflict).where(
        ContentConflict.status == status).order_by(
        ContentConflict.created_at.desc()).limit(100)))


@router.patch("/conflicts/{conflict_id}", response_model=ConflictOut)
async def resolve_conflict(conflict_id: UUID, body: ConflictResolveIn, request: Request,
                           db: DbSession, admin: Admin):
    _require_editor(admin)
    c = await db.get(ContentConflict, conflict_id)
    if c is None:
        raise not_found("Conflict not found")
    before = {"status": c.status}
    c.status = body.status
    c.resolution_notes = body.notes
    await _audit(db, admin, "content.conflict_resolve", entity_type="content_conflict",
                 entity_id=c.id, before=before,
                 after={"status": c.status}, request=request)
    return c


@router.get("/versions", response_model=list[dict])
async def list_versions(db: DbSession, admin: Admin,
                        entity_type: str | None = None,
                        entity_id: UUID | None = None,
                        limit: int = Query(default=25, ge=1, le=100)):
    q = select(ContentVersion).order_by(ContentVersion.created_at.desc()).limit(limit)
    if entity_type:
        q = q.where(ContentVersion.entity_type == entity_type)
    if entity_id:
        q = q.where(ContentVersion.entity_id == entity_id)
    return [{"id": str(v.id), "entity_type": v.entity_type,
             "entity_id": str(v.entity_id), "version": v.version,
             "origin": v.origin, "snapshot_state": v.snapshot_state,
             "change_reason": v.change_reason, "proposal_id": str(v.proposal_id)
             if v.proposal_id else None, "created_at": v.created_at.isoformat(),
             "payload": v.payload}
            for v in await db.scalars(q)]


@router.get("/usage", response_model=dict)
async def ai_usage(db: DbSession, admin: Admin,
                   days: int = Query(default=30, ge=1, le=365)):
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = list((await db.execute(
        select(AiUsageLog.provider, AiUsageLog.model, AiUsageLog.purpose,
               func.count().label("calls"),
               func.coalesce(func.sum(AiUsageLog.prompt_tokens), 0).label("prompt_tokens"),
               func.coalesce(func.sum(AiUsageLog.completion_tokens), 0).label("completion_tokens"),
               func.coalesce(func.sum(AiUsageLog.estimated_cost_usd), 0.0).label("cost"),
               func.avg(AiUsageLog.latency_ms).label("avg_latency_ms"),
               func.sum(sa_text("case when status='error' then 1 else 0 end")).label("errors"))
        .where(AiUsageLog.created_at >= since)
        .group_by(AiUsageLog.provider, AiUsageLog.model, AiUsageLog.purpose)))
        .all())
    per_model = [{"provider": r.provider, "model": r.model, "purpose": r.purpose,
                  "calls": int(r.calls), "prompt_tokens": int(r.prompt_tokens),
                  "completion_tokens": int(r.completion_tokens),
                  "estimated_cost_usd": round(float(r.cost), 6),
                  "avg_latency_ms": round(float(r.avg_latency_ms or 0), 1),
                  "errors": int(r.errors or 0)} for r in rows]
    totals = {"days": days, "calls": sum(x["calls"] for x in per_model),
              "errors": sum(x["errors"] for x in per_model),
              "estimated_cost_usd": round(sum(x["estimated_cost_usd"] for x in per_model), 6),
              "provider": get_settings().ai_provider,
              "model": get_ai_service().model_version}
    return {"totals": totals, "per_model": per_model}


@router.post("/copilot", response_model=CopilotOut)
async def copilot(body: CopilotIn, request: Request, db: DbSession, admin: Admin):
    _require_editor(admin)
    result = await pipeline.copilot(db, body.prompt, admin)
    await _audit(db, admin, "content.copilot", entity_type="copilot",
                 entity_id=None, after={"prompt": body.prompt[:160],
                                        "proposals": result["proposals"]},
                 request=request)
    return result


@router.get("/search", response_model=list[dict])
async def knowledge_search(db: DbSession, admin: Admin,
                           q: str = Query(min_length=2, max_length=160),
                           kind: str = Query(default="knowledge"),
                           top: int = Query(default=10, ge=1, le=25)):
    """Retrieval for admins (and, in later phases, for generation context):
    vector cosine when embeddings exist, keyword search always. Never sends
    whole documents to the model — top-k snippets only."""
    provider = get_ai_service()
    vec = (await provider.embed([q]))[0] if provider.embed_supported else None

    def cosine(a, b) -> float:
        return sum(x * y for x, y in zip(a, b))

    if kind == "chunks":
        rows = list(await db.scalars(select(SourceChunk).limit(500)))
        scored = []
        for c in rows:
            kw = sum(1 for w in norm_prompt(q).split() if w in c.text.lower())
            score = cosine(vec, c.embedding) if vec and c.embedding else kw * 0.1
            if score > 0 or kw > 0:
                scored.append((max(score, kw * 0.1), c))
        scored.sort(key=lambda x: -x[0])
        return [{"document_id": str(c.document_id), "position": c.position,
                 "page_start": c.page_start, "page_end": c.page_end,
                 "chapter_ref": c.chapter_ref, "score": round(s, 4),
                 "snippet": c.text[:220]} for s, c in scored[:top]]

    like = f"%{norm_prompt(q)}%"
    rows = list(await db.scalars(select(KnowledgeItem).where(or_(
        KnowledgeItem.title.ilike(f"%{q}%"), KnowledgeItem.body.ilike(like))).limit(100)))
    return [{"id": str(k.id), "category": k.category, "title": k.title,
             "confidence": k.confidence, "topic_key": k.topic_key,
             "status": k.status, "body": k.body[:280]} for k in rows[:top]]
